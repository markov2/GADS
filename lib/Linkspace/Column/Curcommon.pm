## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Curcommon;
# Extended by ::Autocur and ::Curval

use Log::Report       'linkspace';
use Scalar::Util      qw/blessed/;

use Linkspace::Filter ();
use Linkspace::Util   qw/is_valid_id/;

use Moo;
extends 'Linkspace::Column';

### 2021-02-11: columns in GADS::Schema::Result::Curval
# id           value        child_unique layout_id    record_id

### 2021-02-11: columns in GADS::Schema::Result::CurvalField
# id         child_id   parent_id

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

sub _column_extra_update($%)
{   my ($self, $extra, %args) = @_;
    $self->SUPER::_column_extra_update($extra, %args);

    my $curval_columns = $self->layout->columns(delete $extra->{curval_columns});
    @$curval_columns or return $self;

    my @curval_column_ids;
    my $refers_to_sheet_id;

    foreach my $column (@$curval_columns)
    {   next if $column->type eq 'curval'; # can't refer recursively

        $refers_to_sheet_id //= $column->sheet_id;
        $refers_to_sheet_id == $column->sheet_id
            or error "Column '{col.name}' is from a different sheet", col => $column;

        my %link = (parent_id => $self->id, child_id => $column->id);

        $::db->get_record(CurvalField => \%link)
            or $::db->create(CurvalField => \%link);

        push @curval_column_ids, $column->id;
    }

    # Then delete any that no longer exist
    my %search = ( parent_id => $self->id );
    $search{child_id} = { '!=' =>  [ -and => @curval_column_ids ] }
        if @curval_column_ids;

    $::db->delete(CurvalField => \%search);
}

###
### Instance
###

sub tjoin
{   my ($self, %options) = @_;
    $self->make_join(map $_->tjoin, grep !$_->is_internal,
        @{$self->curval_columns_retrieve(%options)});
}

has curval_sheet => (
    is => 'lazy',
    builder => sub { $_[0]->curval_columns->[0]->sheet }
);

has _curval_column_ids_index => (
    is      => 'lazy',
    builder => sub { +{ map +($_->id => $_), @{$_[0]->curval_columns} } },
);

sub curval_column_ids { [ map $_->id, @{$_[0]->curval_columns} ] }  # ordered

has curval_columns => (
    is      => 'lazy',
    builder => sub
      { my $self = shift;
        my @col_ids = $::db->search(CurvalField => { parent_id => $self->id })
            ->get_column('child_id')->all;
        $self->layout->columns(\@col_ids);   # returns position ordered columns
      },
);

sub has_curval_column($) { exists $_[0]->_curval_column_ids_index->{$_[1]} }

sub sort_columns { [ map $_->sort_columns, @{$_[0]->curval_columns} ] }

sub datum_as_string($)
{   my ($self, $datum) = @_;

    # When the curval_cells are multivalue as well, they also produce comma-
    # separated strings.  When this datum is in a mulitvalue cell, these
    # strings will be joined with ', ' as well.  So: the comma can have three
    # meanings.  It does confuse the sorting order.
    join ', ', map $_->as_string, @{$datum->curval_cells };
}

=pod

# Work out the columns we need to retrieve for the records that are a part of
# this value. We try and retrieve the minimum possible. This may be just the
# selected columns of the column, or it may need more: in the case of a curval
# we may need all columns for an edit, or if the value is being used within
# a calc column then we will also need more.   XXX This could be further
# improved, so as only retrieving the code columns that are needed.

sub curval_columns_retrieve
{   my ($self, %options) = @_;
    return $self->curval_columns if !$options{all_columns};
    my $ret =  $self->curval_columns_all;

    # Prevent recursive loops of columns that refer to each other
    my @ret = grep !$options{already_seen}{$_->id}, @$ret;
    $options{already_seen}{$_->id} = 1 for @ret;
    \@ret;
}

has filtered_values => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        $self->value_selector eq 'dropdown'   or return [];
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

{   my ($self, $ids) = @_;
    my $rows = $self->_get_rows($ids);
    map { $self->_format_row($_) } @$rows;
}

sub column_values_for_code
{   my ($self, %options) = @_;
    my $already_seen_code = $options{already_seen_code};
    my $values = $self->column_values(@_, all_columns => 1);
#XXX my @cells =

    my @retrieve_cols = grep $_->name_short,
         @{$self->curval_columns_retrieve(all_columns => 1)};

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
# $cell->for_code
        }
    }

    $return;
}

#XXX must be moved (partially?) to ::Datum
sub column_values
{   my ($self, %params) = @_;
    my $rows       = $params{rows};
    my $all_columns = $params{all_columns};
    my $level      = $params{level};
    my $seen       = $params{already_seen_code};  # returned de-dup

    # $param{all_columns}: retrieve all columns of the rows. If the column of the
    # row hasn't been built with all_columns, then we'll need to retrieve all
    # the columns (otherwise only the ones defined for display in the record
    # will be available).  The rows would normally only need to be retrieved
    # when a single record is being written.

    my @rows;     # rows to be returned
    my @need_ids; # IDs of those records that need to be fully retrieved

    # See if any of the requested rows have not had all columns built and
    # therefore a rebuild is required
    if ($all_columns && $rows)
    {   my @cur_retrieve = $self->curval_column_ids_retrieve(all_columns => $all_columns);
        # We have full database rows, so now let's see if any of them were not
        # build with the all columns flag.
        # Those that need to be retrieved
        #XXX use parted
        @need_ids = map $_->current_id,
            grep ! $_->has_columns(@cur_retrieve),
                @$rows;

        # Those that don't can be added straight to the return array
        @rows = grep $_->has_columns(@cur_retrieve), @$rows;
    }
    elsif($all_columns)
    {   # This section is if we have only been passed IDs, in which case we
        # will need to retrieve the rows
        @need_ids = @{$params{ids}};
    }

    if(@need_ids)
    {   # If all columns needed, flag that in the column properties. This
        # allows it to be checked later
        $self->retrieve_all_columns(1) if $all_columns;
        push @rows, @{$self->_get_rows(\@need_ids)};
    }
    elsif($rows)
    {   # Just use existing rows
        @rows = @$rows;
    }
    else
    {   panic "Neither rows nor ids passed to all_column_values";
    }

    my %data;
    my $cols = $self->curval_columns_retrieve(all_columns => $all_columns);
    foreach my $row (@rows)
    {
        my %datums;
        # Curval values that have not been written yet don't have an ID
        next if !$row->current_id;
        foreach my $col (@$row)
        {   my $col_id = $col->id;

            # Prevent recursive loops. It's possible that a curval and autocur
            # column will recursively refer to each other. This is complicated
            # by calc columns including these - when the values to pass into the
            # code are generated, we check that we're not producing recursively
            # inside each other. Calc and rag columns can have input columns that
            # refer back to this (e.g. curval has a code column, the code column
            # has an autocur column, the autocur refers back to the curval).
            #
            # Check whether the column has already been seen, but ensure that it
            # was seen at a different recursive level to where we are now. This
            # is because for multivalue curval columns, the same column will be
            # seen multiple times for multiple records at the same array level.

            next if $seen->{$col_id} && $seen->{$col_id} != $level;
            $datums{$col_id} = $row->column($col)
                or panic __x"Missing column {name}. Was Records build with all columns?", name => $col->name;
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
    my $columns = $self->curval_columns;

    # First create a view to search for this value in the column.
    my @conditions = map +{
        column    => $_->id,
        id       => $_->id,
        type     => $_->type,
        value    => $match,
        operator => $_->return_type eq 'string' ? 'begins_with' : 'equal',
    }, @$columns;

    my $filter = Linkspace::Filter->from_hash( +{
            condition => 'AND',
            rules     => [
                +{ condition => 'OR', rules => \@conditions },
                $self->filter->sub_values($self->layout->records),
            ],
        },
    );

my $view;
    my $page = $related_sheet->content->search(
        rows    => 10,
        view    => $view,
        columns => $columns,
        filter  => $match ? $filter : undef,
    );

    map +{ id => $_->{id}, name => $_->{name} },
        map $self->_format_row($_, value_key => 'name'),
            @{$page->rows};
}

sub _format_row
{   my ($self, $row, %options) = @_;
    my $value_key = $options{value_key} || 'value';
    my $columns   = $self->curval_columns;

my $row
    +{
        id         => $row->id,
        record     => $row,
        $value_key => $self->format_value(@values),
        values     => [ grep $_->has_permission('read'), @$columns ],
    };
}

sub format_value
{   shift;
    join ', ', map +($_ || ''), @_;
}

=cut

sub export_hash()
{   my $self = shift;
    $self->SUPER::export_hash(@_,
        refers_to_sheet_id => $self->related_sheet->id,
        curval_column_ids   => [ map $_->id, $self->curval_columns ],
    );
}

1;
