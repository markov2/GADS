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
use List::Util      qw(first);
use Linkspace::Util qw(index_by_id);

use Moo;
use MooX::Types::MooseLike::Base qw/ArrayRef HashRef/;

extends 'Linkspace::Column';
use namespace::clean;

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue { 1 }
sub fixedvals      { 1 }
sub has_filter_typeahead { 1 }
sub retrieve_fields      { [ qw/id value deleted/] }

###
### Class
###

sub remove($)
{   my $col_id = $_[1]->id;
    # Rely on tree cleanup instead. If we have our own here, then
    # it may error for tree types if the rows reference parents.
}

###
### Instance
###

sub sprefix        { 'value' }
sub tjoin          { +{ $_[0]->field => 'value' } }
sub value_field_as_index { 'id' }

has enumvals => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        my $order = $self->ordering || '';
        my $sort
            = $order eq 'asc'  ? 'me.value'
            : $order eq 'desc' ? { -desc => 'me.value' }
            : ['me.position', 'me.id'];

        my $enumvals = $::db->search(Enumval => {
            layout_id    => $self->id,
            deleted      => 0,
        }, {
            order_by     => $sort,
            result_class => 'HASH',
        });
        [ $enumvals->all ];
    },
);

sub column_update_extra($)
{   my ($self, $extra) = @_;

    # Deal with submitted values straight from a HTML form. These will be
    # *all* submitted parameters, so we need to pull out only the relevant
    # ones.  We submit like this and not using a single array parameter to
    # ensure we keep the IDs intact.
    my @enumvals_in = @{$values->{enumvals}};
    my @enumval_ids = @{$values->{enumval_ids}};

    my @enumvals;
    foreach my $v (@enumvals_in)
    {   my $id = shift @enumval_ids;
        push @enumvals, $id
          ? +{ value => $v, id => $id }
          : +{ value => $v };            # new
    }

    \@enumvals;
)

sub id_as_string
{   my ($self, $id) = @_;
    $id or return '';
    $self->enumval($id)->{value};
}

sub string_as_id
{   my ($self, $value) = @_;
    my @vals = $::db->search(Enumval => {
        layout_id => $self->id,
        deleted   => 0,
        value     => $value,
    })->all;

    @vals < 2
        or error __x"More than one value for {value} in field {name}",
            value => $value, name => $self->name;

    @vals
        or error __x"Value {value} not found in field {name}",
            value => $value, name => $self->name;

    $vals[0];
}

# Indexed list of enumvals
has _enumvals_index => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { index_by_id $_[0]->enumvals },
);

has ordering => (
    is  => 'rw',
    isa => sub {
        !defined $_[0] || $_[0] eq "desc" || $_[0] eq "asc"
            or error "Invalid enum order value: {ordering}", ordering => $_[0];
    }
);

after build_values => sub {
    my ($self, $original) = @_;
    $self->ordering($original->{ordering});
};

sub write_special
{   my ($self, %options) = @_;

    my $id           = $options{id};
    my $rset         = $options{rset};
    my $enum_mapping = $options{enum_mapping};

    my $position;
    foreach my $en (@{$self->enumvals})
    {
        my $value = $en->{value};
        error __x"{value} is not a valid value for an item of a drop-down list",
            value => ($value ? qq('$value') : 'A blank value')
            unless $value =~ /^[ \S]+$/;
        $position++;
        if($en->{id})
        {
            my $enumval = $options{create_missing_id}
              ? $::db->resultset('Enumval')->find_or_create({ id => $en->{id}, layout_id => $id })
              : $::db->resultset('Enumval')->find($en->{id});
            $enumval or error __x"Bad ID {id} for multiple select update", id => $en->{id};
            $enumval->update({ value => $value, position => $en->{position} || $position });
        }
        else
        {   my $new = $::db->create(Enumval => {
                value     => $en->{value},
                layout_id => $id,
                position  => $en->{position} || $position,
            });
            $en->{id} = $new->id;
        }

        $enum_mapping->{$en->{source_id}} = $en->{id}
            if $enum_mapping;
    }

    # Then delete any that no longer exist
    $self->_delete_unused_nodes;
    $rset->update({ ordering => $self->ordering });

    return ();
};

sub validate
{   my ($self, $value, %options) = @_;
    return 1 if !$value || defined $self->enumval($value);

    return 0 unless $options{fatal};
    error __x"'{int}' is not a valid enum ID for '{col}'",
        int => $value, col => $self->name;
}

# Any value is valid for a search, as it can include begins_with etc
sub validate_search {1};

sub enumval
{   my ($self, $id) = @_;
    $id ? $self->_enumvals_index->{$id} : undef;
}

sub random
{   my $self = shift;
    my $hash = $self->_enumvals_index;
    keys %$hash or return;
    $hash->{(keys %$hash)[rand keys %$hash]}->{value};
}

sub _enumvals_from_form
{   my $self = shift;

}

sub _delete_unused_nodes
{   my $self = shift;

    my @all = $::db->search(Enumval => { layout_id => $self->id })->all;

    foreach my $node (@all)
    {
        next if $node->deleted; # Already deleted
        first { $node->id == $_->{id} } @{$self->enumvals})
            or next;

        my $count = $::db->search(Enum => {
            layout_id => $self->id,
            value     => $node->id
        })->count; # In use somewhere

        if($count)
        {   $node->update({ deleted => 1 });
        }
        else
        {   $node->delete;
        }
    }
}

sub resultset_for_values
{   my $self = shift;
    $::db->search(Enumval => { layout_id => $self->id, deleted => 0 });
}

sub additional_pdf_export
{   my $self = shift;
    my $enums = join ', ', map $_->{value}, @{$self->enumvals};
    [ 'Select values', $enums ];
}

before import_hash => sub {
    my ($self, $values, %options) = @_;
    my $report = $options{report_only} && $self->id;
    my @new = @{$values->{enumvals}};
    my @to_write;

    # Sort by IDs so that the imported values have been created in the same
    # order as they were created in the source system. This means that if
    # further imports/exports are done, that it is possible to compare
    # better (as above) and work out what has been created and updated
    @new = sort { $a->{id} <=> $b->{id} } @new;

    # We have no unqiue identifier with which to match, so we have to compare
    # the new and the old lists to try and work out what's changed. Simple
    # changes are handled automatically, more complicated ones will require
    # manual intervention
    if (my @old = @{$self->enumvals})
    {
        @old = sort { $a->{id} <=> $b->{id} } @old;

        # First see if there are any changes at all
        my @old_sorted = sort map $_->{value}, @old;
        my @new_sorted = sort map $_->{value}, @new;

        # We shouldn't need to do this as it should just be handled below, but
        # some older imports imported enumvals in a different order to the
        # source system (now fixed) so the import routines below don't function
        # as they expect enum values in a consistent order
        if (@old_sorted eq @new_sorted)
        {
            foreach my $old (@old)
            {
                my $new = shift @new;
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
                    trace __x"No change for enum value {value}", value => $old->{value}
                        if $report;
                    $new->{source_id} = $new->{id};
                    $new->{id} = $old->{id};
                    push @to_write, $new;
                    next;
                }

                # Different. Is the next one the same?
                if ($old[0] && $new[0] && $old[0]->{value} eq $new[0]->{value})
                {
                    # Yes, assume the previous is a value change
                    notice __x"Changing enum value {old} to {new}", old => $old->{value}, new => $new->{value}
                        if $report;
                    $new->{source_id} = $new->{id};
                    $new->{id} = $old->{id};
                    push @to_write, $new;
                }
                elsif ($options{force})
                {
                    notice __x"Unknown enumval update {value}, forcing as requested", value => $new->{value};
                    $new->{source_id} = delete $new->{id};
                    push @to_write, $new;
                }
                else
                {   # Different, don't know what to do, require manual intervention
                    if ($report)
                    {
                        notice __x"Error: don't know how to handle enumval updates for {name}, manual intervention required. Old value: {old}, new value: {new}",
                            name => $self->name, old => $old->{value}, new => $new->{value};
                        return;
                    }
                    else
                    {   error __x"Error: don't know how to handle enumval updates for {name}, manual intervention required",
                            name => $self->name;
                    }
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

sub export_hash
{   my $self = shift;
    $self->SUPER::export_hash(@_,
       enumvals => $self->enumvals,
       ordering => $self->ordering,
    );
}

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

