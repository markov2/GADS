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

use Linkspace::Util qw(index_by_id normalize_string);

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
<delete_unused_enumvals()> will clean-up deleted enumvals which are not used in
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
    my $order = $args{order} || $self->ordering || 'position';
    my @vals  = values %{$self->_enumvals};
    @vals     = grep ! $_->deleted, @vals unless $args{include_deleted};

      $order eq 'asc'      ? [ sort { $a->value cmp $b->value } @vals ]
    : $order eq 'desc'     ? [ sort { $b->value cmp $a->value } @vals ]
    : $order eq 'position' ? [ sort { $a->position <=> $b->position } @vals ]
    : panic $order;
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
{   my ($self, $extra, %args) = @_;
    $self->SUPER::_column_extra_update($extra);

    # Deal with submitted values, also straight from a HTML form.
    # Two arrays: names (which may contain new names) and ids (which show
    # order).  The ids also tell us under which number an enum is already
    # known: that may result in name changes.  Double names are 

    my $names    = delete $extra->{enumvals};
    my $ids      = delete $extra->{enumval_ids} || [];
    $names or return;

    my @names    = map normalize_string($_), @$names;
    my $enumvals = $self->_enumvals;
    my %missing  = map +($_ => 1), keys %$enumvals;
    my $position = 0;

    my @ids      = @$ids;

  ENUM:
    foreach my $name (@names)
    {   $position++;

        if(my $enum_id = shift @ids)
        {   delete $missing{$enum_id};
            my $rec = $enumvals->{$enum_id};
            next if $rec->value eq $name && $rec->position==$position && !$rec->deleted;
    
            if($rec->value ne $name)
            {   if(!$enum_id && grep { $name eq $_->value } values %$enumvals)
                {   # Duplicate names will cause horrors, but may exist in old servers.
                     info  __x"column {col.path} duplicate enum '{name}' ignored",
                         col => $self, name => $name;
                     next ENUM;
                }
    
                info __x"column {col.path} rename enum '{from}' to '{to}'",
                   col => $self, from => $rec->value, to => $name;
                $rec->value($name);
            }
    
            if($rec->deleted)
            {   info __x"column {col.path} deleted enum '{name}' revived",
                   col => $self, name => $name;
                $rec->deleted(0);
            }
    
            $rec->position($position);  # unreported
            $rec->update({deleted => 0, value => $name, position => $position });
        }
        else
        {   my $r = $::db->create(Enumval => { value => $name, position => $position});
            info __x"column {col.path} add enum '{name}'",
                col => $self, name => $name;
            $enumvals->{$r->id} = $::db->get_record(Enumval => $r->id);
        }
    }

    foreach my $enum_id (keys %missing)
    {   my $rec = $enumvals->{$enum_id};
        $rec->update({deleted => 1, position => ++$position});
        info __x"column {col.path} withdraw option '{enum.value}'", col => $self, enum => $rec;
        $rec->deleted(1);
    }

    $self->delete_unused_enumvals unless $args{keep_unused};
    $self;
}

sub id_as_string($)
{   my ($self, $id) = @_;
    my $enum = $id ? $self->_enumvals->{$id} : undef;
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

=head2 $column->enumval_in_use($enum_id);
=cut

sub enumval_in_use($)
{   my ($self, $val) = @_;
    $::db->search(Enum => {layout_id => $self->id, value => $val->id })->count;
}

=head2 $column->delete_unused_enumvals;
Deleted enums stay alive as long as they are still in use (in the history) of
records.  Every once in a while, we recheck whether they are still needed.
=cut

sub delete_unused_enumvals
{   my $self = shift;
    my $enumvals = $self->_enumvals;

    foreach my $node (values %$enumvals)
    {   next if ! $node->deleted || $self->enumval_in_use($node);

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
