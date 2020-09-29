=pod
GADS - Globally Accessible Data Store
Copyright (C) 2017 Ctrl O Ltd

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

package Linkspace::Column::Curcommon;
# Extended by ::Autocur and ::Curval

use Log::Report       'linkspace';
use Scalar::Util      qw/blessed/;

use Linkspace::Filter ();
use Linkspace::Util   qw/is_valid_id/;

use Moo;
extends 'Linkspace::Column';

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue { 1 }
sub has_fixedvals  { 1 }
sub has_filter_typeahead { 1 }
sub is_curcommon   { 1 }
sub is_multivalue  { 1 }
sub sort_parent    { shift }   # me!
sub variable_join  { 1 }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Curval      => { layout_id => $col_id });
    $::db->delete(CurvalField => { parent_id => $col_id });
}

sub _column_create($)
{   my ($class, $insert) = @_;

    $insert->{related_field_id} || $insert->{related_field}
        or error __x"Please select a field that refers to this table";

    $class->SUPER::_column_create($insert);
}

sub _column_update($)
{   my ($self, $update) = @_;
    my $curval_fields = delete $update{curval_fields}
                     || delete $update{curval_field_ids};

    $self->SUPER::column_update($update);
    defined $curval_fields or return $self;

#XXX to be moved to Linkspace::Column::Curcommon::Reference
    # Skip fields not part of referred instance. This can happen when a
    # user changes the instance that is referred to, in which case fields
    # may still be selected and submitted from the no-longer-displayed
    # table's list of fields

    my $parent_sheet_id  = $self->layout_parent->sheet_id;
    my @curval_fields    = grep $_->sheet_id == $parent_sheet_id,
        @{$self->columns($curval_fields)};

    my @curval_field_ids;
    foreach my $column (@curval_fields)
    {
        # Check whether field is a curval - can't refer recursively
        next if $column->type eq 'curval';

        my %link = (parent_id => $column->id, child_id => $field);

        $::db->get_record(CurvalField => \%link)
            or $::db->create(CurvalField => \%link);

        push @curval_field_ids, $column->id;
    }

    # Then delete any that no longer exist
    my %search = (parent_id => $id);
    $search{child_id} = { '!=' =>  [ -and => @curval_field_ids ] }
        if @curval_field_ids;

    $::db->delete(CurvalField => \%search);

}

###
### Instance
###

sub tjoin
{   my ($self, %options) = @_;
    $self->make_join(map $_->tjoin, grep !$_->is_internal,
        @{$self->curval_fields_retrieve(%options)});
}

has layout_parent => (
    is      => 'lazy',
    builder => sub { my $p = $_[0]->related_field; $p ? $p->layout : $p } },
);

has retrieve_all_columns => (
    is      => 'rw',
    isa     => Bool,
    default => 0,
);

has _curval_field_ids_index => (
    is      => 'lazy',
    builder => sub { +{ map +($_ => undef), @{$_[0]->curval_field_ids} } },
);

has curval_field_ids => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        my $curval_field_ids = $::db->search(CurvalField => {
            parent_id => $self->id,
        }, {
            join     => 'child',
            order_by => 'child.position',
        })->get_column('child_id');
        [ $curval_field_ids->all ];
    },
);

sub curval_fields()
{   my $self = shift;
    $self->layout_parent->columns($self->curval_field_ids, permission => 'read');
}

sub has_curval_field
{   my ($self, $field) = @_;
    exists $self->_curval_field_ids_index->{$field};
}

has curval_field_ids_all => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $columns = $self->layout_parent->columns_search(internal => 0);

        #XXX probably, the caller of this wants something else
        [  map $_->id, @$columns ];
    },
);

sub curval_field_ids_retrieve
{   my ($self, %options) = @_;
    [ map $_->id, @{$self->curval_fields_retrieve(%options)} ];
}

# Work out the columns we need to retrieve for the records that are a part of
# this value. We try and retrieve the minimum possible. This may be just the
# selected columns of the field, or it may need more: in the case of a curval
# we may need all columns for an edit, or if the value is being used within
# a calc field then we will also need more.   XXX This could be further
# improved, so as only retrieving the code fields that are needed.
sub curval_fields_retrieve
{   my ($self, %options) = @_;
    return $self->curval_fields if !$options{all_fields};
    my $ret =  $self->curval_fields_all;

    # Prevent recursive loops of fields that refer to each other
    my @ret = grep !$options{already_seen}{$_->id}, @$ret;
    $options{already_seen}{$_->id} = 1 for @ret;
    \@ret;
};

has curval_fields_all => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $all    = $self->curval_field_ids_all;
        my $parent = $self->layout_parent;
        [ map $parent->column($_, permission => 'read'), @$all ];
    }
}

sub sort_columns
{   my $self = shift;
    [ map $_->sort_columns, @{$self->curval_fields} ];
}

has filtered_values => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        $self->value_selector eq 'dropdown' or return [];
        my $records = $self->_records_from_db or return [];
        [ map $self->_format_row($_), $records->all ];
    },
);

has all_values => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        $self->value_selector eq 'dropdown' or return [];
        my $records = $self->_records_from_db(no_filter => 1) or return [];
        [ map $self->_format_row($_), $records->all ];
    },
);

sub _records_from_db
{   my ($self, %options) = @_;

    my $ids = $options{ids};

    # $ids is optional
    panic "Entering curval _build_values and PANIC_ON_CURVAL_BUILD_VALUES is true"
        if !$ids && $ENV{PANIC_ON_CURVAL_BUILD_VALUES};

    # Not the normal request layout
    my $layout = $self->layout_parent
        or return; # No layout or fields set

    my $view;
    if (!$ids && !$options{no_filter})
    {
#XXX view from filter
#XXX       $self->filter->sub_values($layout->record);
    }

    # Sort on all columns displayed as the Curval. Don't do all columns
    # retrieved, as this could include a whole load of multivalues which
    # are then fetched from the DB

    my $records = $sheet->content->search(
        view              => $view,
        columns           => $self->curval_field_ids_retrieve(all_fields => $self->retrieve_all_columns),
        limit_current_ids => $ids,
        sort              => $self->curval_columns,
        is_draft          => 1, # XXX Only set this when parent record is draft?
    );

    return $records;
}

# Function to return the values for the drop-down selector, but only the
# selected ones. This makes rendering the edit page quicker, as in the case of
# a filtered drop-down, the values will be fetched each time it gets the
# focus anyway
sub selected_values
{   my ($self, $datum) = @_;
    [ map $self->_format_row($_->{record}), @{$datum->values} ];
}

has values_index => (
    is        => 'lazy',
    predicate => 1,
    builder   => sub { +{ map +($_->{id} => $_->{value}), @{$_[0]->all_values} } },
);

sub filter_value_to_text
{   my ($self, $id) = @_;
    # Check for valid ID (in case search filter is corrupted) - Pg will choke
    # on invalid IDs
    is_valid_id $id or return '';

    # Exceptions are raised if trying to convert an invalid ID into a value.
    # This can happen when a filter has been set up and then its referred-to
    # curval record is deleted
    my $text = try {
        my ($row) = $self->ids_to_values([$id]);
        $row->{value};
    };
    $text;
}

sub id_as_string
{   my ($self, $id) = @_;
    $id or return '';
    my @vals =  $self->ids_to_values([$id]);
    $vals[0]->{value};
}

# Used to return a formatted value for a single datum. Normally called from a
# Datum::Curval object
sub ids_to_values
{   my ($self, $ids) = @_;
    my $rows = $self->_get_rows($ids);
    map { $self->_format_row($_) } @$rows;
}

sub field_values_for_code
{   my $self = shift;
    my %options = @_;
    my $already_seen_code = $options{already_seen_code};
    my $values = $self->field_values(@_, all_fields => 1);

    my @retrieve_cols = grep $_->name_short,
         @{$self->curval_fields_retrieve(all_fields => 1)};

    my $return = {};

    foreach my $cid (keys %$values)
    {
        foreach my $col (@retrieve_cols)
        {
            my $d = $values->{$cid}->{$col->id} or next;

            # Ensure that the "global" (within parent datum) already_seen
            # hash is passed around all sub-datums.
            $d->already_seen_code($already_seen_code);

            # As we delve further into more values, increase the level for
            # each curval/autocur
            $d->already_seen_level($options{level} + ($col->is_curcommon ? 1 : 0));
            $return->{$cid}->{$col->name_short} = $d->for_code;
        }
    }

    $return;
}

sub field_values
{   my ($self, %params) = @_;
    my $rows       = $params{rows};
    my $all_fields = $params{all_fields};
    my $level      = $params{level};
    my $seen       = $params{already_seen_code};  # returned de-dup

    # $param{all_fields}: retrieve all fields of the rows. If the column of the
    # row hasn't been built with all_columns, then we'll need to retrieve all
    # the columns (otherwise only the ones defined for display in the record
    # will be available).  The rows would normally only need to be retrieved
    # when a single record is being written.

    my @rows;     # rows to be returned
    my @need_ids; # IDs of those records that need to be fully retrieved

    # See if any of the requested rows have not had all columns built and
    # therefore a rebuild is required
    if ($all_fields && $rows)
    {   my @cur_retrieve = $self->curval_field_ids_retrieve(all_fields => $all_fields);
        # We have full database rows, so now let's see if any of them were not
        # build with the all columns flag.
        # Those that need to be retrieved
        #XXX use parted
        @need_ids = map $_->current_id,
            grep ! $_->has_fields(@cur_retrieve),
                @$rows;

        # Those that don't can be added straight to the return array
        @rows = grep $_->has_fields(@cur_retrieve), @$rows;
    }
    elsif($all_fields)
    {   # This section is if we have only been passed IDs, in which case we
        # will need to retrieve the rows
        @need_ids = @{$params{ids}};
    }

    if(@need_ids)
    {   # If all columns needed, flag that in the column properties. This
        # allows it to be checked later
        $self->retrieve_all_columns(1) if $all_fields;
        push @rows, @{$self->_get_rows(\@need_ids)};
    }
    elsif($rows)
    {   # Just use existing rows
        @rows = @$rows;
    }
    else
    {   panic "Neither rows nor ids passed to all_field_values";
    }

    my %data;
    my $cols = $self->curval_fields_retrieve(all_fields => $all_fields);
    foreach my $row (@rows)
    {
        my %datums;
        # Curval values that have not been written yet don't have an ID
        next if !$row->current_id;
        foreach my $col (@$row)
        {   my $col_id = $col->id;

            # Prevent recursive loops. It's possible that a curval and autocur
            # field will recursively refer to each other. This is complicated
            # by calc fields including these - when the values to pass into the
            # code are generated, we check that we're not producing recursively
            # inside each other. Calc and rag fields can have input fields that
            # refer back to this (e.g. curval has a code field, the code field
            # has an autocur field, the autocur refers back to the curval).
            #
            # Check whether the field has already been seen, but ensure that it
            # was seen at a different recursive level to where we are now. This
            # is because for multivalue curval fields, the same field will be
            # seen multiple times for multiple records at the same array level.

            next if $seen->{$col_id} && $seen->{$col_id} != $level;
            $datums{$col_id} = $row->field($col)
                or panic __x"Missing field {name}. Was Records build with all fields?", name => $col->name;
            $seen->{$col->id} = $level;
        }
        $data{$row->current_id} = \%datums;
    }
    \%data;
}

sub _get_rows
{   my ($self, $ids, %options) = @_;
    @$ids or return;
    if(my $index = $self->has_values_index) # Do not build unnecessarily (expensive)
    {   return [ map $index->{$_}, @$ids ];
    }

    my $rows = $self->_records_from_db(ids => $ids, %options)->results;
    error __x"Invalid Curval ID list {ids}", ids => "@$ids"
        if @$rows != @$ids;

    $rows;
}

sub validate_search
{   my ($self, $value, %options) = @_;
    $value
        or error __x"Search value cannot be blank for {col.name}.", col => $self;

    is_valid_id $value
        or error __x"Search value must be an ID number for {col.name}.", col => $self;

    1;
}

sub values_beginning_with
{   my ($self, $match) = @_;
    my $fields = $self->curval_fields;

    # First create a view to search for this value in the column.
    my @conditions = map +{
        field    => $_->id,
        id       => $_->id,
        type     => $_->type,
        value    => $match,
        operator => $_->return_type eq 'string' ? 'begins_with' : 'equal',
    }, @$fields;

    my $filter = Linkspace::Filter->from_hash( +{
            condition => 'AND',
            rules     => [
                +{ condition => 'OR', rules => \@conditions },
                $self->filter->sub_values($self->layout->records),
            ],
        },
    );

    my $page = $related_sheet->content->search(
        rows    => 10,
        view    => $view,
        columns => $fields,
        filter  => $match ? $filter : undef,
    );

    map +{ id => $_->{id}, name => $_->{name} },
        map $self->_format_row($_, value_key => 'name'),
            @{$page->rows};
}

sub _format_row
{   my ($self, $row, %options) = @_;
    my $value_key = $options{value_key} || 'value';
    my $fields    = $self->curval_fields;

    +{
        id         => $row->current_id,
        record     => $row,
        $value_key => $self->format_value(@values),
        values     => [ grep $_->has_permission('read'), @$fields ],
    };
}

sub format_value
{   shift;
    join ', ', map +($_ || ''), @_;
}

sub export_hash()
{   my $self = shift;
    $self->SUPER::export_hash(@_,
        refers_to_instance_id => $self->related_sheet_id,
        curval_field_ids      => [ map $_->id, $self->curval_columns ],
    );
}

1;
