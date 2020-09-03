=pod
GADS - Globally Accessible Data Store
Copyright (C) 2014 Ctrl O Ltd

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=cut

package Linkspace::Column::Enum;

use Log::Report     'linkspace';
use List::Util      qw(first max);

use Linkspace::Util qw(index_by_id);

use Moo;
extends 'Linkspace::Column';

#------------- Helper tables
# Enumval is used to define the enum options: the value is a name.  The Enum
# table contains the Enum datums.
#
### 2020-09-01: columns in GADS::Schema::Result::Enum
# id           value        child_unique layout_id    record_id
#
### 2020-09-01: columns in GADS::Schema::Result::Enumval
# id         value      deleted    layout_id  parent     position

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue  { 1 }
sub has_fixedvals   { 1 }
sub form_extras     { [ 'ordering' ], [ qw/enumvals enumval_ids/ ] }
sub has_filter_typeahead { 1 }
sub retrieve_fields { [ qw/id value deleted/] }
sub db_field_extra_export { [ qw/ordering/ ] }

###
### Class
###

sub remove_column($)
{   my $col_id = $_[1]->id;
    # Rely on tree cleanup instead. If we have our own here, then
    # it may error for tree types if the rows reference parents.
}

###
### Instance
###

sub sprefix  { 'value' }
sub tjoin    { +{ $_[0]->field => 'value' } }
sub value_field_as_index { 'id' }

#------------------
=head2 METHODS: Enum

Two tables: the C<Enumval> contains, per column, a set of options (strings
in field C<value>).  The C<Enum> contains the enum datums (cell values).

When an enum option is deleted, it does not get removed but flagged as 'deleted'.
It may happen that (historical) cells still contain the value.  Sometimes, the
<remove_unused_deleted()> will clean-up deleted enumvals which are not used in
any cell anymore.

=cut

has _enumvals => (
    is      => 'lazy',
    builder => sub {
       index_by_id $::db->search(Enumval => { layout_id => $_[0]->id })->all;
    },
);

#! Returns HASHes
sub enumvals(%)
{   my ($self, %args) = @_;
    my $order = $args{order} || $self->ordering || '';
    my @vals  = values %{$self->_enumvals};
    @vals     = grep ! $_->deleted, @vals unless $args{include_deleted};

      $order eq 'asc'  ? [ sort { $a->value cmp $b->value } @vals ]
    : $order eq 'desc' ? [ sort { $b->value cmp $a->value } @vals ]
    :              [ sort { $a->position <=> $b->position } @vals ];
}

sub enumval($)
{   my ($self, $id) = @_;
    $id ? $self->_enumvals_index->{$id} : undef;
}

sub enumvals_string(%)
{   my $self = shift;
    join ', ', map $_->value, @{$self->enumvals(@_)};
}

sub _column_extra_update($)
{   my ($self, $extra) = @_;
    $self->SUPER::_column_extra_update($extra);

    # Deal with submitted values straight from a HTML form. These will be
    # *all* submitted parameters, so we need to pull out only the relevant
    # ones.  We submit like this and not using a single array parameter to
    # ensure we keep the IDs intact.
    my $names = delete $extra->{enumvals};
    my $ids   = delete $extra->{enumval_ids} || delete $extra->{enumval_id} || [];
    $names or return;

    my $enumvals = $self->_enumvals;
    my %missing  = map +($_ => 1), keys %$enumvals;
    my $free_pos = max +(map $_->position, values %$enumvals), 0;

    my @ids      = @$ids;
    foreach my $name (@$names)
    {   if(my $enum_id = shift @ids)
        {   delete $missing{$enum_id};
            my $rec = $enumvals->{$enum_id};
            if($rec->value ne $name || $rec->deleted)
            {   $::db->update(Enumval => $rec->id, { deleted => 0, value => $name });
                info __x"column {col.path} rename enum option {from} to {to}",
                    col => $self, from => $rec->value, to => $name;
                $rec->deleted(0);
                $rec->value($name);
            }
        }
        else
        {   my $r = $::db->create(Enumval => { value => $name, position => ++$free_pos});
            info __x"column {col.path} add enum option {name}",
               col => $self, name => $name;
            $enumvals->{$r->id} = $::db->get_record(Enumval => $r->id);
        }
    }

    foreach my $enum_id (keys %missing)
    {   my $rec = $enumvals->{$enum_id};
        $::db->update(Enumval => $rec->id, { deleted => 1 });
        info __x"column {col.path} withdraw option {enum.value}", col => $self, enum => $rec;
        $rec->{deleted} = 1;
    }

#   $self->remove_unused_deleted;
    $self;
}

sub id_as_string
{   my ($self, $id) = @_;
    my $enum = $id ? $self->_enumvals->{$id} : undef;
    $enum ? $enum->value : undef;
}

sub _is_valid_value($)
{   my ($self, $value) = @_;
    if($value !~ /\D/)
    {   $self->_enumvals->{$value}
           or error __x"Enum ID {id} not a known for '{col.name}'", id => $value, col => $self;
        return $value;
    }

    my $found = first { $_->value eq $value } values %{$self->_enumvals};
    $found
        or error __x"Enum name '{name}' not a known for '{col.name}'", name => $value, col => $self;

    $found->id;
}

#XXX used?
sub random
{   my $self  = shift;
    my $vals  = $self->_enumvals;
    my $count = keys %$vals or return;
    $vals->{(keys %$vals)[rand $count]}->{value};
}

=head2 $column->remove_unused_deleted;
Deleted enums stay alive as long as they are still in use (in the history) of
records.  Every once in a while, we recheck whether they are still needed.
=cut

sub remove_unused_deleted
{   my $self = shift;
    my $enumvals = $self->_enumvals;

    foreach my $node (grep $_->deleted, values %$enumvals)
    {   my $count = $::db->search(Enum => {
            layout_id => $self->id,
            value     => $node->id,
        })->count; # In use somewhere

        next if $count;

        info __x"column {col.path} removed unused option {enum.value}",
            col => $self, enum => $node;

        delete $enumvals->{$node->id};
        $node->delete;
    }
}

sub export_hash
{   my $self = shift;
    my $h = $self->SUPER::export_hash(@_);
    $h->{enumvals} = $self->enumvals;
    $h;
}

sub additional_pdf_export
{   [ 'Select values', $_[0]->enumvals_string(order => 'position') ];
}

sub _import_hash_extra($%)
{   my ($self, $values, %options) = @_;
    my $h = $self->SUPER::_import_hash_extra($values, %options);

    # Sort by IDs so that the imported values have been created in the same
    # order as they were created in the source system. This means that if
    # further imports/exports are done, that it is possible to compare
    # better (as above) and work out what has been created and updated
    my @new = sort { $a->{id} <=> $b->{id} } @{$values->{enumvals}};

    # We have no unqiue identifier with which to match, so we have to compare
    # the new and the old lists to try and work out what's changed. Simple
    # changes are handled automatically, more complicated ones will require
    # manual intervention
    my @to_write;
    if(my @old = sort { $a->{id} <=> $b->{id} } @{$self->enumvals})
    {
        # First see if there are any changes at all
        my @old_sorted = sort map $_->{value}, @old;
        my @new_sorted = sort map $_->{value}, @new;

        # We shouldn't need to do this as it should just be handled below, but
        # some older imports imported enumvals in a different order to the
        # source system (now fixed) so the import routines below don't function
        # as they expect enum values in a consistent order
        if("@old_sorted" eq "@new_sorted")
        {
            foreach my $old (@old)
            {   my $new = shift @new;
                $old->{source_id} = $new->{id};
                push @to_write, $old;
            }
        }
        else
        {   while (@old)
            {
                my $old = shift @old;
                my $new = shift @new;
                # If it's the same, easy, onto the next one
                if ($old->{value} eq $new->{value})
                {
                    trace __x"No change for enum value {value}", value => $old->{value};
                    $new->{source_id} = $new->{id};
                    $new->{id} = $old->{id};
                    push @to_write, $new;
                    next;
                }

                # Different. Is the next one the same?
                if ($old[0] && $new[0] && $old[0]->{value} eq $new[0]->{value})
                {
                    # Yes, assume the previous is a value change
                    notice __x"Changing enum value {old} to {new}", old => $old->{value}, new => $new->{value};
                    $new->{source_id} = $new->{id};
                    $new->{id} = $old->{id};
                    push @to_write, $new;
                }
                elsif($options{force})
                {
                    notice __x"Unknown enumval update {value}, forcing as requested", value => $new->{value};
                    $new->{source_id} = delete $new->{id};
                    push @to_write, $new;
                }
                else
                {   # Different, don't know what to do, require manual intervention
                    error __x"Error: don't know how to handle enumval updates for {name}, manual intervention required",
                        name => $self->name;
                }
            }

            # Add any remaining new ones
            $_->{source_id} = delete $_->{id} for @new;
            push @to_write, @new;
        }
    }
    else
    {   $_->{source_id} = delete $_->{id} for @new;
        @to_write = @new;
    }

    $self->enumvals(\@to_write);
    $self->ordering($values->{ordering});
};

sub import_value
{   my ($self, $value) = @_;

    $::db->create(Enum => {
        layout_id    => $self->id,
        record_id    => $value->{record_id},
        child_unique => $value->{child_unique},
        value        => $value->{value},
    });
}

1;
