## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Row::Revision;

use Log::Report 'linkspace';

use JSON          qw(encode_json);
use CtrlO::PDF    ();
use PDF::Table    ();
use URI::Escape   qw(uri_escape_utf8);
use Scalar::Util  qw(blessed);
use List::Util    qw(max);
use DateTime      ();

use Linkspace::Row::Cell ();
use Linkspace::Util      qw(index_by_id to_id);
use Linkspace::Row::Cell ();
use Linkspace::Row::Cell::Linked ();


use Moo;
extends 'Linkspace::DB::Table';

sub db_table { 'Record' }

sub db_field_rename { +{
    approval   => 'needs_approval',
    approvedby => 'approved_by_id',
    createdby  => 'created_by_id',
    record_id  => 'approval_base_id',
} };

__PACKAGE__->db_accessors;

### 2020-10-28: columns in GADS::Schema::Result::Current
# id           deleted      draftuser_id parent_id
# instance_id  deletedby    linked_id    serial

### 2020-06-30: columns in GADS::Schema::Result::Record
# id         approvedby createdby  record_id
# approval   created    current_id
#XXX The created and createdby fields should have been part of the Current
#XXX table.  Now they get copied all the time.

#---------------
=head1 NAME

Linkspace::Row::Revision - manage a row in the data of a sheet

=head1 DESCRIPTION
An existing row may have additional to-be-approved datums, which will overwrite
existing values once someone with approval rights agrees on them.  When those
datums exist, the C<needs_approval> attribute is set.

=head2 METHODS: Constructors
=cut

sub _revision_create($$%)
{   my ($class, $row, $insert, %args) = @_;
    $args{timestamp} ||= DateTime->now;
    $args{user}      ||= $::session->user;
    my $user_cells = delete $insert->{cells} || [];
    my $previous   = delete $args{is_initial} ? undef : $row->current;

    my $cells      = $class->_complete_cells($row, $previous, delete $args{cells}, %args);
    my $grouped_cells = $class->_group_cells($row, $previous, $cells);

    if(@{$grouped_cells->{need_approval}})
    {   $class .= '::Approval';
        $insert->{needs_approval} = 1;
        $insert->{approval_base}  = $previous;
    }

    if($previous)
    {   $insert->{created_by} ||= $previous->created_by;
        $insert->{created}    ||= $previous->created;
    }
    else
    {   $insert->{created_by} ||= $args{user};
        $insert->{created}    ||= $args{timestamp};
    }

    $insert->{current_id}     ||= $row->id;
    $insert->{needs_approval} ||= 0;

    my $self = $class->create($insert, %args,
        row        => $row,
        is_initial => ! $previous,
    );

    $self->_create_cells($grouped_cells);

    $self;
}

sub _complete_cells($$$%)
{   my ($self, $row, $previous, $pairs, %args) = @_;
    my @pairs  = ref $pairs eq 'HASH' ? %$pairs : @{$pairs || []};
    my $layout = $row->layout;

    # We do not need to create datums for the other internals
    unshift @pairs,
        _version_user     => $args{user},
        _version_datetime => $args{timestamp};

    my %datums;

    while(@pairs)
    {   my $name   = shift @pairs;
        my $column = $layout->column($name) or panic $name;
        my $values = shift @pairs;

        $values    = $values->values     # I value this line
            if blessed $values && $values->isa('Linkspace::Row::Cell');

        $values    = ! defined $values ? [] : [ $values ]
            if ref $values ne 'ARRAY';

        my $old    = $previous ? $previous->cell($column)->datums : [];
        my $datums = $column->values2datums($values, $old);
        @$datums or next;

        ! $datums{$column->id}
            or error __x"Column {col.name_short} specified twice", col => $column;

        $datums{$column->id} = $datums;
    }

    my @cells;
    my $columns = $row->layout->columns_search;
    my $allow_incomplete = $row->is_draft;

    foreach my $column (@$columns)
    {   my $datums = delete $datums{$column->id} || [];

        if($column->is_userinput)
        {   @$datums || $allow_incomplete || $column->is_optional
                or error __x"Column {col.name} requires a value.", col => $column;

            @$datums < 2 || $column->is_multivalue
                or error __x"Column {col.name} can only contain one value.", col => $column;
        }
        elsif(@$datums && ! $column->is_internal)
        {   error __x"Column {col.name} has a computed value.", col => $column;
        }

        push @cells, [ $column, $datums ] if @$datums;
    }

    error __x"Unexpected column {col.name_short}", col => $_->[0]
        for values %datums;

    \@cells;
}

sub _group_cells($%)
{   my ($class, $row, $previous, $cells, %args) = @_;

    my $row_is_new    = ! $previous;
    my $row_is_linked = !! $row->linked_row_id;
    my $row_is_draft  = $row->is_draft;

    my ($write, $approve) = $row_is_new
      ? ('write_new_no_approval', 'approve_new')
      : ('write_existing_no_approval', 'approve_existing');

    my ($internal, $writable, $need_approve, $compute, $linked) = ([],[],[],[],[]);

    foreach (@$cells)
    {   my ($column, $datums) = @$_;

        my $queue
          = $column->is_internal        ? $internal
          : ! $column->is_userinput     ? $compute
          : $row_is_linked && $column->linked_column_id ? $linked
          : $row_is_draft               ? $writable
          : $column->user_can($write) || $column->user_can($approve)    ? $writable
          : $previous && $previous->cell($column)->same_values($datums) ? $writable
          :                               $need_approve;

        push @$queue, [ $column, $datums ];
    }

  +{ internal      => $internal,
     writable      => $writable,
     need_approval => $need_approve,
     need_compute  => $compute,
     linked        => $linked,
   };
}

sub _create_cells($@)
{   my ($self, $grouped, %args) = @_;
    my $cells = $self->_cells;

    foreach my $group (qw/internal writable need_approval linked need_compute/)
    {   my $cells = $grouped->{$group} or panic;
        @$cells or next;

        if($group eq 'need_compute')
        {  ...;
        }

        foreach my $datums (map $_->[1], @$cells)
        {   $_->write($self) for @$datums;
        }
    }
}

#--------------------
sub _revision_latest(%)
{   my ($class, %args) = @_;

    my %search = ( current => $args{row}, needs_approval => 0 );
    if(my $before = delete $args{created_before})
    {   $search{created}   = { '<=', $before };
        $args{is_historic} = 1;
    }

    my $rec = $::db->resultset(Record => \%search, { order => { -desc => 'created', limit => 1 } })->next;
    $class->from_record($rec, is_historic => 0, %args);

#   my $latest_id = $::db->resultset(Record => \%search, {)->get_column('created')->max;
#   $class->from_id($latest_id, is_historic => 0, %args);
}

sub _revision_first_id(%)
{   my $self = shift;
    $self->resultset({current_id => $self->current_id})->get_column('id')->min;
}

sub _find($%)
{   my ($class, $row, %args) = @_;
    my %search = (current => $row, needs_approval => 0);

    if(my $before = $args{created_before})
    {   $search{created} = { '<' => $before };
    }

    $class->search_objects(
        \%search, { order_by => { -desc => 'created' }},
        row => $row,
    );
}

sub _revision_delete
{   my $self = shift;
    Linkspace::Datum->remove_values_stored_for($self);
    $self->user->row_remove_cursors($self);
#XXX remove cells

    $self->delete;
}

#---------------
=head2 METHODS: Attributes
=cut

sub path() { $_[0]->row->path . '/rev=' . $_[0]->id }

has row => ( is => 'ro', required => 1 );

has _columns_retrieved_index => (
    is      => 'lazy',
    builder => sub { index_by_id $_[0]->columns_retrieved_do },
);

has created_by => (
    is      => 'lazy',
    builder => sub { $_[0]->site->users->user($_[0]->created_by_id) },
);

=head2 $rev->is_initial;
Returns true when this is the initial revision being build: there is no
active accepted revision yet.
=cut

has is_initial => (
    is      => 'lazy',
    builder => sub { ! $_[0]->row->current },
);

=head2 $rev->is_historic;
Returns true when this revision is not the current revision of the row.
=cut

has is_historic => (
    is      => 'lazy',
    builder => sub { $_[0]->row->current->id != $_[0]->id },
);


#---------------
=head2 METHODS: Handling Cells
=cut

has _cells => (
    is      => 'lazy',
    builder => sub { +{} },
);

sub cell($)
{   my ($self, $which) = @_;
    my $column = $self->column($which) or return;
    my $cell   = $self->_cells->{$column->id};
    return $cell if $cell;

    my $cell_class = $column->link_column_id
       ? 'Linkspace::Row::Cell::Linked'
       : 'Linkspace::Row::Cell';

    $cell = $cell_class->new(
        revision => $self,
        column   => $column,
        datums   => $self->datums($column),
    );

    $self->_cells->{$column->id} = $cell;
}

# Croaks on multivalue fields
sub value($)
{   my $self = shift;
    my $cell = $self->cell(shift) or return;
    $cell->value;
}

sub values($)
{   my $self = shift;
    my $cell = $self->cell(shift) or return;
    $cell->values;
}

=pod
# XXX This whole section is getting messy and duplicating a lot of code from
# GADS::Records. Ideally this needs to share the same code.
sub _find
{   my ($self, %find) = @_;

    my $is_draft = !! $find{draftuser_id};
    my $record_id = $find{record_id};

    my $results = $self->sheet->content->search(
        curcommon_all_cells => $self->curcommon_all_cells,
        columns             => $self->columns,
        is_deleted          => $find{deleted},
        is_draft            => $is_draft || $find{include_draft},
        no_view_limits      => $is_draft,
        include_approval    => $self->include_approval,
        include_children    => 1,
        view_limit_extra_id => undef, # Remove any default extra view
    );

    my $record = {}; my $limit = 10; my $first_run = 1;
    my $page = 1;

    while (1)
    {
        # No linked here so that we get the ones needed in accordance with this loop (could be either)
        my @prefetches = $content->jpfetch(prefetch => 1, search => 1, limit => $limit, page => $page); # Still need search in case of view limit
        last if !@prefetches && !$first_run;
        my $search     = $find{current_id} || $find{draftuser_id}
            ? $content->search_query(prefetch => 1, linked => 1, limit => $limit, page => $page)
            : $content->search_query(root_table => 'record', prefetch => 1, linked => 1, limit => $limit, no_current => 1, page => $page);
        @prefetches = $content->jpfetch(prefetch => 1, search => 1, linked => 0, limit => $limit, page => $page); # Still need search in case of view limit


        my $root_table;
        if($record_id)
        {
            unshift @prefetches, (
                {
                    current => [
                        'deletedby',
                        $content->linked_hash(prefetch => 1, limit => $limit, page => $page),
                    ],
                },
            ); # Add info about related current record
            push @$search, { 'me.id' => $record_id };
            $root_table = 'Record';
        }
        elsif ($find{current_id} || $find{draftuser_id})
        {
            if($find{current_id})
            {   push @$search, { 'me.id' => $find{current_id} };
            }
            elsif($find{draftuser_id})
            {   push @$search, { 'me.draftuser_id' => $find{draftuser_id} },
                               { 'curvals.id'      => undef };
            }

            @prefetches = (
                $content->linked_hash(prefetch => 1, limit => $limit, page => $page),
                'deletedby',
                'currents',
                {
                    record_single => [
                        'record_later',
                        @prefetches,
                    ],
                },
            );
            $root_table = 'Current';
        }
        else {
            panic "record_id or current_id needs to be passed to _find";
        }

        local $GADS::Schema::Result::Record::REWIND = $content->rewind_formatted
            if $content->rewind;

        # Don't specify linked for fetching columns, we will get whatever is needed linked or not linked
        my @columns_fetch = $content->columns_fetch(search => 1, limit => $limit, page => $page); # Still need search in case of view limit
        my $has_linked = $content->has_linked(prefetch => 1, limit => $limit, page => $page);

        if($record_id)
        {   push @columns_fetch,
              { id           => "me.id" },
              { deleted      => "current.deleted" },
              { linked_id    => "current.linked_id" },
              { draftuser_id => "current.draftuser_id" },
              { current_id   => "me.current_id" },
              { created      => "me.created" };
        }
        else
        {   my $base = $has_linked ? 'record_single_2' : 'record_single';
            push @columns_fetch,
              { id           => "$base.id" },
              { deleted      => "me.deleted" },
              { linked_id    => "me.linked_id" },
              { draftuser_id => "me.draftuser_id" },
              { current_id   => "$base.current_id" },
              { created      => "$base.created" };
        }

        push @columns_fetch, "deletedby.$_"
            for Linkspace::Column::Person->person_properties;

        # If fetch a draft, then make sure it's not a draft curval that's part of
        # another draft record
        push @prefetches, 'curvals' if $find{draftuser_id};

        my @recs = $::db->search($root_table =>
            [
                -and => $search
            ],
            {
                join    => \@prefetches,
                columns => \@columns_fetch,
                result_class => 'HASH',
            },
        )->all;

        return if !@recs && $find{no_errors};
        @recs or error __"Requested record not found";

        # We shouldn't normally receive more than one record here, as multiple
        # values for single cells are retrieved separately. However, if a
        # field was previously a multiple-value field, and it was subsequently
        # changed to a single-value field, then there may be some remaining
        # multiple values for the single-value field. In that case, multiple
        # records will be returned from the database.
        foreach my $rec (@recs)
        {
            foreach my $key (keys %$rec)
            {
                # If we have multiple records, check whether we already have a
                # value for that field, and if so add it, but only if it is
                # different to the first (the ID will be different)
                if ($key =~ /^field/ && (my $has = $record->{$key}))
                {   my @existing = grep $_->{id}, flat $has;

                    push @existing, $rec->{$key}
                        if ! grep $rec->{$key}->{id} == $_->{id}, @existing;
                    $record->{$key} = \@existing;
                }
                else
                {   $record->{$key} = $rec->{$key};
                }
            }
        }
        $page++;
        $first_run = 0;
    }

    $self->linked_id($record->{linked_id});
    $self->set_deleted($record->{deleted});
    $self->set_deletedby($record->{deletedby});
    $self->clear_is_draft;

    # Find the user that created this record.
    my $first = $row->revision('first');
    if(my $creator = $first->created_by)
    {   $self->set_record_created_user({$creator->get_columns})
    }

    # Fetch and merge and multi-values
    my @record_ids = $record->{id};
    push @record_ids, $record->{linked}->{record_id}
        if $record->{linked} && $record->{linked}->{record_id};

    # Related record if this is approval record
    $new->{approval_base_id} = $record->{record_id}
        if $new->{needs_approval} = $record->{approval};

    my $new_rev = (ref $self)->_revision_create($new);

    # Fetch and add multi-values
    $records->fetch_multivalues(
        record_ids           => \@record_ids,
        retrieved            => [ $record ],
        revisions            => [ $new_rev ],
        is_draft             => $find{draftuser_id},
        curcommon_all_cells => $self->curcommon_all_cells,
    );

    $new_rev;
}

sub _transform_values
{   my ($self, $row, $values, %args) = @_;

    # If any columns are multivalue, then the values will not have been
    # prefetched, as prefetching can result in an exponential amount of
    # rows being fetched from the database in one go. It's better to pull
    # all types of value together though, so we store them in this hashref.
    my $multi_values = {};

    # We must do these columns in dependent order, otherwise the
    # column values may not exist for the calc values.

    foreach my $column (@{$self->columns_retrieved_do})
    {   next if $column->is_internal;
        my $key = ($column->link_parent || $column)->field_name;

        # If this value was retrieved as part of a grouping, and if it's a sum,
        # then the field key will be appended with "_sum". XXX Ideally we'd
        # have a better way of knowing this has happened, but this should
        # suffice for the moment.
        if($self->is_grouping)
        {   if($column->is_numeric)
            {   $key .= "_sum";
            }
            elsif(!$self->grouping_cols->{$column->id})
            {   $key .= "_distinct";
            }
        }

        #XXX $original in either case
        my $value = $self->linked_record_raw && $column->link_parent && !$self->is_historic
          ? $self->linked_record_raw->{$key}
          : $original->{$key};

        my $child_unique = ref $value eq 'ARRAY' && @$value > 0
            ? $value->[0]->{child_unique} # Assume same for all parts of value
            : ref $value eq 'HASH' ? $value->{child_unique}
            : undef;

        my %params = (
            record           => $self,
            record_id        => $self->record_id,
            current_id       => $self->current_id,
            child_unique     => $child_unique,
            column           => $column,
        );

        # For curcommon cells, flag that this field has had all its columns if
        # that is what has happened. Then we know during any later process of
        # this column that there is no need to retrieve any other columns
        $column->retrieve_all_columns(1)
            if $self->curcommon_all_cells && $column->is_curcommon;

        my $class = $self->is_grouping && !$column->is_numeric && !$self->grouping_cols->{$column->id}
            ? 'Linkspace::Datum::Count'
            : $column->datum_class;

        $cells{$column->id} = $class->new(%params);
    }


    \%cells;
}

=cut

sub delete_user_drafts($)
{   my ($self, $sheet) = @_;
    my $user = $::session->user;

    $user->has_draft($sheet)
        or return;

    while (1)
    {   my $draft = $self->_sibling_record(user_permission_override => 1);

        $draft->find_draftuser($user, instance_id => $self->sheet->id)
            or last;

        # Find and delete any draft subrecords associated with this draft
        my @curval = map $draft->cell($_),
            grep $_->type eq 'curval', $draft->columns;

        $draft->purge;
        $_->purge_drafts for @curval;
    }
}

# options (mostly used by onboard):
# - update_only: update the values of the existing record instead of creating a
#   new version. This allows updates that aren't recorded in the history, and
#   allows the correcting of previous versions that have since been changed.
# - force_mandatory: allow blank mandatory values
# - no_change_unless_blank: bork on updates to existing values unless blank
# - no_alerts: do not send any alerts for changed values
# - version_datetime: write version date as this instead of now
# - version_userid: user ID for this version if override required
# - missing_not_fatal: whether missing mandatory values are not fatal (but still reported)
# - submitted_cells: an array ref of the cells to check on initial
#   submission. Fields not contained in here will not be checked for missing
#   values. Used in conjunction with missing_not_fatal to only report on some
#   cells

sub _revision_update($$%)
{   my ($self, $update, $row, %args) = @_;

=pod

my $sheet = $row->sheet;
    my $is_draft = $args{draft};

    my $parent_row = $args{parent};

    my $update_only = $self->sheet->forget_history || $args{update_only};

    # This will be called before a write for a normal edit, to allow checks on
    # next/prev values, but we call it here again now, for other writes that
    # haven't explicitly called it
    $self->set_blank_dependents;

    # First loop round: sanitise and see which if any have changed
    my %allow_update = map +($_ => 1), @{$args{allow_update} || []};

    # Whether any topics cannot be written because of missing cells in other topics.
    my %no_write_topics;

    my $cols = $args{submitted_cells}
       || $self->sheet->layout->columns_search(exclude_internal => 1);

    my $child_unique = 0;
    foreach my $column (grep $_->is_userinput, @$cols)
    {   my $datum = $self->cell($column)
            or next; # Will not be set for child records

        # Check for blank value
        if (   $datum->is_blank
            && (!$row->parent_row_id || $column->can_child)
            && !$row->linked_row_id
            && ! $column->is_optional && !$args{force_mandatory}
            && ! $is_draft
            &&  $column->user_can('write')

            # Do not require value if the field has not been shown because of
            # display condition
            && $datum->dependent_shown
        )
        {   my $topic = $column->topic;
            if($topic && $topic->prevent_edit_topic)
            {   # This setting means that we can write this missing value, but we
                # will be unable to write another topic later
                my $t = $no_write_topics{$topic->id} ||= { topic => $topic };
                push @{$t->{columns}}, $column;
            }
            elsif($self->new_entry || $datum->changed)
            {   my $msg = __x"'{col.name}' is required. Please enter a value.", col => $column;
                error $msg unless $args{missing_not_fatal};
                report { is_fatal => 0 }, ERROR => $msg;
            }
            else
            {   # Only warn if it was previously blank, otherwise it might
                # be a read-only field for this user
                mistake __x"'{col.name}' is no longer optional, but was previously blank for this record.", col => $column;
            }
        }

        if($datum->changed)
        {   if($self->doing_approval)
            {   if($self->approval_of_new)
                {   $column->user_can('approve_new')
                       or error __x"You do not have permission to approve new rows";
                }
                else
                {   $column->user_can('approve_existing')
                       or error __x"You do not have permission to approve edits of existing rows";
                }
            }
            elsif($self->new_entry)
            {   $datum->is_blank || $column->user_can('write_new')
                    or error __x"You do not have permission to add data to field {col.name}", col => $column;
            }
            elsif($column->user_can('write_existing'))
            {
            }
            elsif($datum->is_blank && $self->parent_row_id)
            {   # If the user does not have write access to the field, but has
                # permission to create child records, then we want to allow them
                # to add a blank field to the child record. If they do, they
                # will land here, so we check for that and only error if they
                # have entered a value.
                # Force new record to write if this is the only change
                $need_rec = 1;
            }
            else
            {   error __x"You do not have permission to edit field {col.name}", col => $column;
            }
        }

        #  Check for no change option, used by onboarding script
        if ($args{no_change_unless_blank} && !$self->new_entry && $datum->changed && !$datum->oldvalue->is_blank)
        {
            error __x"Attempt to change {name} from \"{old}\" to \"{new}\" but no changes are allowed to existing data",
                old => $datum->oldvalue->as_string, new => $datum->as_string, name => $column->name
                if !$allow_update{$column->id}
                && lc $datum->oldvalue->as_string ne lc $datum->as_string
                && $datum->oldvalue->as_string;
        }

        # Don't check for unique if this is a child record and it hasn't got a unique value.
        # If the value has been de-selected as unique, the datum will be changed, and it
        # may still have a value in it, although this won't be written.
        if (     $column->is_unique
            &&  !$datum->is_blank
            && ( $self->is_new_entry || $datum->changed)
            && (!$self->parent_id || $column->can_child))
        {
            # Check for other columns with this value.
            foreach my $val (@{$datum->search_values_unique})
            {
                if (my $r = $self->find_unique($column, $val))
                {
                    # as_string() used as will be encoded on message display
                    error __x(qq(Field "{field}" must be unique but value "{value}" already exists in record {id}),
                        field => $column->name, value => $datum->as_string, id => $r->current_id);
                }
            }
        }

        # Set any values that should take their values from the parent record.
        # These are are set now so that any subsquent code values have their
        # dependent values already set.
        if($parent_row && !$column->can_child && $column->is_userinput)
        {   # Calc values always unique
            my $parent_cell = $parent_row->cell($column);
            $datum->set_value($parent_cell->values, is_parent_value => 1);
        }

        if ($self->doing_approval)
        {   # See if the user has something that could be approved
            $need_rec = 1 if $self->approver_can_action_column($column);
        }
        elsif ($self->new_entry)
        {
            # New record. Approval needed?
            if($column->user_can('write_new_no_approval') || $is_draft)
            {
                # User has permission to not need approval
                $need_rec = 1;
            }
            elsif ($column->user_can('write_new'))
            {   # This needs an approval record
                trace __x"Approval needed because of no immediate write access to column {id}",
                    id => $column->id;
                $need_app = 1;
                $datum->is_awaiting_approval(1);
            }
        }
        elsif ($datum->changed)
        {
            # Update to record and the field has changed
            # Approval needed?
            if ($column->user_can('write_existing_no_approval'))
            {   $need_rec = 1;
            }
            elsif ($column->user_can('write_existing'))
            {   # This needs an approval record
                trace __x"Approval needed because of no immediate write access to column {id}",
                    id => $column->id;
                $need_app = 1;
                $datum->is_awaiting_approval(1);
            }
        }
        $child_unique = 1 if $column->can_child;
    }

    my $created_date = $args{version_datetime} || DateTime->now;

    $self->cell('_created')->set_value($created_date, is_parent_value => 1)
        if $self->new_entry;

    if($update_only)
    {
        # Keep original record values when only updating the record, except
        # when the update_only is happening for forgetting version history, in
        # which case we want to record these details
        $self->cell_update(_version_datetime => $created_date, is_parent_value => 1);
        $self->cell_update(_version_user => $createdby, is_parent_value => 1);
    }

    # Test duplicate unique calc values
    foreach my $column (@{$self->sheet->layout->columns})
    {   $column->has_cache && $column->is_uniquei or next;

        my $datum = $self->cell($column);
        if (
               ! $datum->is_blank
            && ($self->new_entry || $datum->changed)
            && (!$self->parent_id # either not a child
                || grep $_->can_child, $column->param_columns # or is a calc value that may be different to parent
            )
        )
        {
            $datum->re_evaluate;
            # Check for other columns with this value.
            foreach my $val (@{$datum->search_values_unique})
            {
                if (my $r = $self->find_unique($column, $val))
                {
                    # as_string() used as will be encoded on message display
                    error __x(qq(Field "{field}" must be unique but value "{value}" already exists in record {id}),
                        field => $column->name, value => $datum->as_string, id => $r->current_id);
                }
            }
        }
    }

    # Check whether any values have been written to topics which cannot be
    # written to yet
    foreach my $topic (CORE::values %no_write_topics)
    {
        foreach my $col ($topic->{topic}->cells)
        {
            error __x"You cannot write to {col} until the following cells have been completed: {cells}",
                col => $col->name, cells => [ map $_->name, @{$topic->{columns}} ]
                    if ! $self->cell($col)->is_blank;
        }
    }

    # Error if child record as no cells selected
    error __"There are no child cells defined to be able to create a child record"
        if $self->parent_id && !$child_unique && $self->new_entry;

    # Anything to update?
    if(   !($need_app || $need_rec || $update_only)
       || $args{dry_run} )
    {
        return;
    }

my $current_id;
my $record_id;   # sequential per sheet

my $content = $row->content;
    # New record?
    if($self->new_entry)
    {   # Delete any drafts first, for both draft save and full save
        #XXX all drafts????
        $content->row_delete($_) for $content->draft_rows
             unless $args{no_draft_delete};

        $current_id = $content->row_create({
            parent_id    => $self->parent_id,
            linked_id    => $self->linked_id,
            draftuser_id => $is_draft && $user_id,
        });
    }

    if($need_app)
    {   my $row = $data->row_create({
            current_id     => $current_id,
            record_id      => $record_id,
            needs_approval => 1,
            created_by     => $user,
        });

        $self->update({approval => $row});
    }

    if($self->new_entry && $user_id && !$args{is_draft})
    {   # New entry, so save record ID to user for retrieval of previous
        # values if needed for another new entry. Use the approval ID id
        # it exists, otherwise the record ID.
        my $row_id = $self->approval_id || $self->record_id;
        $user->row_cursor_point($sheet, $row_id);
    }

    $self->_need_rec($need_rec);
    $self->_need_app($need_app);

=cut

}

=pod

sub write_values
{   my ($self, $row, %options) = @_;

    my $guard = $::db->begin_work;
    my $is_new = $self->new_entry;

    my $is_draft = $row->is_draft;    # Draft records may be incomplete

    # Write all the values
    my %columns_changed = ($row->current_id => []);
    my (@columns_cached, %update_autocurs);

    my $approval_id = $self->approval_id;

    my $layout  = $self->sheet->layout;

    my $columns = $layout->columns_search(order_dependencies => 1, exclude_internal => 1);
    foreach my $column (@$columns)
    {
        # Prevent warnings when writing incomplete calc values on draft
        next if $is_draft && ! $column->is_userinput;

        # Don't write all values if this is a linked record
        next if $self->linked_row && $column->link_column_id;

        my $cell = $self->cell($column);
        if($self->_need_rec || $options{update_only}) # For new records, $need_rec is only set if user has create permissions without approval
        {
            my $v;
            # Need to write all values regardless. This will either be the
            # updated and approved value, if updated before arriving here,
            # or the existing value otherwise
            if ($self->doing_approval)
            {
                # Write value regardless (either new approved or existing)
                $self->_cell_write($column, $datum);

                # Leave records where they are unless this user can
                # action the approval
                $self->approver_can_action_column($column)
                    or next;

                # And delete value in approval record
                $::db->delete($column => {
                    record_id => $approval_id,
                    layout_id => $column->id,
                });
            }
            elsif($column->user_can($is_new ? 'write_new_no_approval' : 'write_existing_no_approval')
                  || !$column->is_userinput
            )
            {
                # Write new value
                $self->_cell_write($column, $datum, %options);
            }
            elsif($is_new)
            {   # Write value. It's a new entry and the user doesn't have
                # write access to this field. This will write a blank
                # value.
                $self->_cell_write($column, $datum) if !$column->is_userinput;
            }
            elsif($column->user_can('write'))
            {   # Approval required, write original value
                panic "update_only set but attempt to hold write for approval"
                    if $options{update_only}; # Shouldn't happen, makes no sense
                $self->_cell_write($column, $datum, old => 1);
            }
            else
            {   # Value won't have changed. Write current value (old
                # value will not be set if it hasn't been updated)
                # Write old value
                $self->_cell_write($column, $datum, %options);
            }

            # Note any records that will need updating that have an autocur field that refers to this
            if ($column->type eq 'curval')
            {
                foreach my $autocur (@{$column->autocurs})
                {
                    # Do nothing with deleted records
                    my %deleted = map { $_ => 1 } @{$datum->ids_deleted};

                    # Work out which ones have changed. We only want to
                    # re-evaluate records that have actually changed, for both
                    # performance reasons and to send the correct alerts
                    #
                    # First, establish which current IDs might be affected
                    my %affected = map { $_ => 1 }
                        grep !$deleted{$_}, @{$datum->ids_affected};

                    # Then see if any cells depend on this autocur (e.g. code cells)
                    if ($autocur->layouts_depend_depends_on->count)
                    {
                        # If they do, we will need to re-evaluate them all
                        $update_autocurs{$_} ||= []
                            foreach keys %affected;
                    }

                    # If the value hasn't changed at all, skip on
                    next unless $datum->changed;

                    # If it has changed, work out which one have been added or
                    # removed. Annotate these with the autocur ID, so we can
                    # mark that as changed with this value
                    foreach my $cid (@{$datum->ids_changed})
                    {   next if $deleted{$cid};
                        push @{$update_autocurs{$cid}}, $autocur->id;
                    }
                }
            }
        }

        if($cell->is_awaiting_approval)
        {   $self->_cell_write($column, $datum, approval => 1)
                if $is_new ? !$datum->is_blank : $datum->changed;
        }
    }

    # Test all internal columns for changes - these will not have been tested
    # during the write above
my $sheet = $self->row->sheet;
    my $internals = $sheet->layout->columns_search(only_internal => 1);
    foreach my $column (@$internals)
    {   push @{$columns_changed{$row->current_id}}, $column->id
            if $self->cell($column)->changed;
    }

my $user = $::session->user;
    # If this is an approval, see if there is anything left to approve
    # in this record. If not, delete the stub record.
    if($self->doing_approval && ! Linkspace::Datum->has_values_stored_for($approval_id))
    {   # Nothing left for this approval record.
        my $cursor = $user->row_cursor($sheet);
        $user->set_row_cursor($sheet, $self)
            if $cursor->revision_id == $approval_id;

        # Delete approval stub
        $::db->delete(Record => $approval_id);
    }

    # Do we need to update any child records that rely on the values of this parent record?
    if(!$options{is_draft})
    {
        my $columns = $self->layout->columns_search(order_dependencies => 1, exclude_internal => 1);

        foreach my $child (@{$self->row->child_rows})
        {   my @updates;
            foreach my $col (@$columns)
            {   $col->is_userinput or next; # Calc/rag will be evaluated during update

                push @updates, [ $col => $child->cell($col)->values ]
                    unless $col->can_child;  #XXX ???
            }
            $child->current->cell_update(\@updates, is_parent_value => 1, update_only => 1);
        }

        # Update any records with an autocur field that are referred to by this
        foreach my $cid (keys %update_autocurs)
        {
            # Check whether this record is one that we're going to write
            # anyway. If so, skip.
            next if grep $_->current_id == $cid, @{$self->_records_to_write_after};

            my $record = $self->_sibling_record;
            $record->find_current_id($cid);
            $record->cell($_)->changed(1) for @{$update_autocurs{$cid}};
            $record->write(%options, update_only => 1, re_evaluate => 1);
        }
    }

    $_->write_values(%options)
        for @{$self->_records_to_write_after};

    # Alerts can cause SQL errors, due to the unique constraints
    # on the alert cache columns. Therefore, commit what we've
    # done so far, and don't do alerts in a transaction
    $guard->commit;

    # Send any alerts
    if(!$options{no_alerts} && ! $is_draft)
    {
        # Possibly not the best way to do alerts, but certainly the
        # simplest. Spin up a new alert sender for each changed record
        foreach my $cid (keys %columns_changed)
        {
            my $alert_send = GADS::AlertSend->new(
                current_ids => [ $cid ],
                columns     => $columns_changed{$cid},
                current_new => !$previous,
            );

            if ($ENV{GADS_NO_FORK})
            {   $alert_send->process;
                return;
            }
            if (my $kid = fork)
            {
                # will fire off a worker and then abandon it, thus making reaping
                # the long running process (the grndkid) init's (pid1) problem
                waitpid($kid, 0); # wait for child to start grandchild and clean up
            }
            else
            {
                if (my $grandkid = fork) {
                    POSIX::_exit(0); # the child dies here
                }
                else
                {   # We should already be in a try() block, probably with
                    # hidden messages. These messages will never be written, as
                    # we exit the process.  Therefore, stop the hiding of
                    # messages for this part of the code.
                    my $parent_try = dispatcher 'active-try'; # Boolean false
                    $parent_try->hide('NONE');

                    # We must catch exceptions here, otherwise we will never
                    # reap the process. Set up a guard to be doubly-sure this
                    # happens.
                    my $guard = guard { POSIX::_exit(0) };

                    # Despite the guard, we still operate in a try block, so as to catch
                    # the messages from any exceptions and report them accordingly.
                    # Only collect messages at warning or higher, otherwise
                    # thousands of trace messages are stored which use lots of
                    # memory.
                    try { $alert_send->process } hide => 'ALL', accept => 'WARNING-'; # This takes a long time
                    $@->reportAll(is_fatal => 0);
                }
            }
        }
    }
}

=cut

sub set_blank_dependents
{   my $self = shift;

    foreach my $column ($self->layout->columns_search(exclude_internal => 1))
    {   my $cell = $self->cell($column);
        $cell->set_values([])
            if ! $cell->dependent_shown
            && ($column->can_child || ! $self->row->parent_id);
    }
}

=pod

    unless($column->is_userinput)
    {   $cell->re_evaluate;
        return;
    }

    # No datum for new invisible cells
    my $child_unique = $datum ? $column->can_child : 0;

    my $layout_id    = $column->id;
    my $row_id       = ($options{approval} ? $self->approval_base : $row)->id;

    my @entries;

    my $datum_write  = $options{old} ? $datum->oldvalue : $datum;
    if ($datum_write)
    {   #XXX field_values() weird side-effects for Curval
        foreach my $v ($column->field_values($datum_write, $self, %options))
        {   $v->{child_unique} = $child_unique;
            $v->{layout_id}    = $layout_id;
            $v->{record_id}    = $row_id;
            push @entries, $v;
        }
    }

    my $table = $column->table;
    if ($options{update_only})
    {
        my @rows = $::db->search($table => {
            record_id => $entry->{record_id},
            layout_id => $entry->{layout_id},
        })->all;

        foreach my $row (@rows)
        {   if(my $entry = pop @entries)
            {   $row->update($entry);
            }
            else
            {   $row->delete; # Now less values than before
            }
        }

        $::db->create($table => $_) for @entries;
    }
}

=cut

sub restore
{   my $self = shift;
    $self->sheet->user_can('purge')
        or error __"You do not have permission to restore records";

    $::db->update(Current => $self->current_id, { deleted => undef });
}

sub as_json
{   my $self = shift;
    my $return;
    my $columns = $self->sheet->layout->columns_search(user_can_read => 1);
    $return->{$_->name_short} = $self->cell($_)->as_string
         for @$columns;

    encode_json $return;
}

sub as_query
{   my ($self, %options) = @_;
    my @queries;
    my $columns = $self->sheet->layout->columns_search(userinput => 1);
    foreach my $col (@$columns)
    {   next if $options{exclude_curcommon} && $col->is_curcommon;
        push @queries, $col->field."=".uri_escape_utf8($_)
            for @{$self->cell($col)->html_form};
    }
    join '&', @queries;
}

sub pdf
{   my $self = shift;
    my $row  = $self->row;
    my $site = $self->site;

    my $now = DateTime->now;
    $now->set_time_zone('Europe/London');

    my $pdf = CtrlO::PDF->new(
        footer => 'Downloaded by ' . $self->user->value . ' on '
                . $site->dt2local($now) .' at '. $now->hms
    );

    my $created = $self->created;
    my $updated = $site->dt2local($created) .' at '. $created->hms;

    $pdf->add_page;
    $pdf->heading('Record '.$self->current_id);
    $pdf->heading('Last updated by '.$self->created_by->as_string ." on $updated", size => 12);

    my @data    = [ 'Field', 'Value' ];
    my $columns = $self->sheet->layout->columns_search(user_can_read => 1);
    foreach my $col (@$columns)
    {   my $cell = $self->cell($col);
        $cell->dependent_shown or next;

        if ($col->is_curcommon)
        {   my $th   = $col->name;
            foreach my $line (@{$cell->values})
            {   my @td = map $_->as_string, @{$line->{values}};
                push @data, [ $th, @td ];
                $th    = '';
            }
        }
        else
        {   push @data, [ $col->name, $cell->as_string ];
        }
    }

    my $max_cells = max map +@$_, @data;

    #XXX not used
    my $hdr_props = {
        repeat     => 1,
        justify    => 'center',
        font_size  => 8,
    };

    my @cell_props;
    foreach my $d (@data)
    {   my $has = @$d;
        # $max_cells does not include field name
        my $gap = $max_cells - $has + 1;
        push @$d, (undef) x $gap;
        push @cell_props, [
            (undef) x ($has - 1),
            +{ colspan => $gap + 1 },
        ];
    }

    $pdf->table(
        data       => \@data,
        cell_props => \@cell_props,
    );

    $pdf;
}
1;
