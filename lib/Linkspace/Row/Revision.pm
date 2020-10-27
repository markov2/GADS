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

use warnings;
use strict;

package Linkspace::Row::Revision;

use Log::Report 'linkspace';

use CtrlO::PDF;
use DateTime;
use DateTime::Format::Strptime qw( );
use JSON qw(encode_json);
use PDF::Table 0.11.0; # Needed for colspan feature
use Session::Token;
use URI::Escape;
use Scalar::Util  qw(blessed);
use DateTime ();

use Linkspace::Util qw(index_by_id);

use Moo;
extends 'Linkspace::DB::Table';

sub db_table { 'Record' }

sub db_field_rename { +{
    approval   => 'needs_approval',
    approvedby => 'approved_by_id',
    createdby  => 'created_by_id',
    record_id  => 'approval_base_id',
} };

### 2020-06-30: columns in GADS::Schema::Result::Record
# id         approvedby createdby  record_id
# approval   created    current_id

#---------------
=head1 NAME

Linkspace::Row::Revision - manage a row in the data of a sheet

=head1 DESCRIPTION
An existing row may have additional to-be-approved datums, which will overwrite
existing values once someone with approval rights agrees on them.  When those
datums exist, the C<needs_approval> attribute is set.

=cut

sub _revision_create($$%)
{   my ($class, $row, $insert, %args) = @_;
    $insert->{created_by} ||= $::session->user unless $insert->{created_by_id};
    $insert->{created}    ||= DateTime->new;
    $insert->{current}    ||= $row;
    $insert->{needs_approval} ||= 0;
    $class->create($insert, @_, row => $row);
}

sub _revision_latest(%)
{   my ($class, %args) = @_;

    my %search = { current => $args{row}, needs_approval => 0 };
    if(my $before = delete $args{created_before})
    {   $search{created}   = { '<=', $before };
        $args{is_historic} = 1;
    }

    my $latest_id = $class->resultset(\%search)->get_column('created')->max;
    $class->from_id($latest_id, %args);
}

sub _revision_first_id(%)
{   my $self = shift;
    $self->resultset({current_id => $self->current_id})->get_column('id')->min;
}

has curcommon_all_cells => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

sub has_cells
{   my ($self, $col_ids) = @_;
    my $index = $self->_columns_retrieved_index;
    ! first { ! $index->{$_} } @$col_ids;
}

has id_count => (
    is      => 'rwp',
);

has _columns_retrieved_index => (
    is      => 'lazy',
    builder => sub { index_by_id $_[0]->columns_retrieved_do },
);

# Value containing the actual columns retrieved.
# In "dependent order", needed for calcvals
has columns_retrieved_do => (
    is => 'rw',
);

has _cells => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        $self->_transform_values;
    },
);

sub cell($)
{   my ($self, $col) = @_;
    my $c = $self->column($col);
    $c ? $self->_cells->{$c->id} : undef;
}

#sub created_by { $_[0]->site->users->user($_[0]->created_by_id) }

sub value($;$)
{   my ($self, $col, $index) = @_;
    my $cell = $self->cell($col);

    # index required for potential multivalue fields
    defined $index || ! $cell->column->can_multivalue or panic;

    $cell->values->[$index || 0];
}

=head2 $rev->is_historic;
Returns true when this revision is not the current revision of the row.
=cut

sub is_historic { $_[0]->row->current->id != $_[0]->id }

sub _build_approval_of_new
{   my ($self, $row) = @_;

    # record_id could either be an approval record itself, or
    # a record. If it's an approval record, get its record
    my $record_id = $self->approval_id || $self->approval_base_id;
    my $record = $row->revision($record_id);

    $::db->search(Record => {
        'me.id'              => $record->id,
        'record_previous.id' => undef,
    },{
        join => 'record_previous',
    })->count;
}

# XXX This whole section is getting messy and duplicating a lot of code from
# GADS::Records. Ideally this needs to share the same code.
sub _find
{   my ($self, %find) = @_;

=pod
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

=cut

}

sub load_remembered_values
{   my ($self, %options) = @_;
    my $user = $::session->user;
    my $sheet = $self->sheet;

    # First see if there's a draft. If so, use that instead
    if($user->has_draft($sheet))
    {
        if($self->find_draftuser($user))
        {   #XXX remove current_id, record_id etc.  Why?
            #XXX $self->remove_id;
            return;
        }
        $self->initialise;
    }

    my @remember = $sheet->layout->columns_search(remember => 1);
    @remember or return;

    my $cursor = $user->row_cursor($sheet)
        or return;

    my $previous = $cursor->row_revision(
        columns          => \@remember,
        include_approval => 1,
    );

    $self->cell($_) = $previous->cell($_)->clone(record => $self, column => $_)
        for @{$previous->columns_retrieved_do};

    if($previous->needs_approval)
    {
        # The last edited record was one for approval. This will
        # be missing values, so get its associated main record,
        # and use the values for that too.
        # There will only be an associated main record if some
        # values did not need approval
        if(my $app_id = $previous->approval_record_id)
        {   my $child = $self->_sibling_record(include_approval => 1);
            $child->find_record_id($app_id);

            my $cells = $self->cells;
            foreach my $col ($sheet->layout->columns_search(user_can_write_new => 1, userinput => 1))
            {
                # See if the record above had a value. If not, fill with the
                # approval record's value
                my $field = $self->cell($col);
                $cells->{$col->id} = $field->clone(record => $self)
                    if ! $field->has_value && $col->remember;
            }
        }
    }
}

sub versions
{   my $self = shift;
    my %search = (
        current_id => $self->current_id,
        approval   => 0,
    );
    $search{'me.created'} = { '<' => $::db->format_datetime($self->rewind) }
        if $self->rewind;

    $::db->search(Record => \%search,
        {   prefetch   => 'createdby',
            order_by   => { -desc => 'me.created' }
        })->all;
}

sub _set_record_id
{   my ($self, $record) = @_;
    $record->{id};    #XXX set?
}

sub _transform_values
{   my ($self, $row) = @_;

    my $original = $self->record or panic "Record data has not been set";

    my $cells = {};
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
            {   $key = $key."_sum";
            }
            elsif(!$self->group_cols->{$column->id})
            {   $key = $key."_distinct";
            }
        }

        #XXX $original in either case
        my $value = $self->linked_record_raw && $column->link_parent && !$self->is_historic
          ? $self->linked_record_raw->{$key}
          : $original->{$key};

        my $child_unique = ref $value eq 'ARRAY' && @$value > 0
            ? $value->[0]->{child_unique} # Assume same for all parts of value
            : ref $value eq 'HASH' && exists $value->{child_unique}
            ? $value->{child_unique}
            : undef;

        my %params = (
            record           => $self,
            record_id        => $self->record_id,
            current_id       => $self->current_id,
            init_value       => ref $value eq 'ARRAY' ? $value : defined $value ? [$value] : [],
            child_unique     => $child_unique,
            column           => $column,
            init_no_value    => $self->init_no_value,
            layout           => $self->layout,
        );
        # For curcommon cells, flag that this field has had all its columns if
        # that is what has happened. Then we know during any later process of
        # this column that there is no need to retrieve any other columns
        $column->retrieve_all_columns(1)
            if $self->curcommon_all_cells && $column->is_curcommon;

        my $class = $self->is_grouping && !$column->is_numeric && !$self->group_cols->{$column->id}
            ? 'GADS::Datum::Count'
            : $column->class;

        $cells->{$column->id} = $class->new(%params);
    }

    $self->_set_id_count($original->{id_count});

my ($serial, $oldest_version_created);
    my %cells = (
        _id               => $row->current_id,
        _version_datetime => $original->{created},
        _version_user     => $original->{createdby} || $original->{_version_user},
        _created_user     => $::session->user,
        _created          => $oldest_version_created,
        _serial           => $serial,
    );

    $cells;
}

sub values_by_shortname
{   my ($self, %params) = @_;
    my $names = $params{names};

    my %index;
    foreach my $name (@$names)
    {   my $col   = $self->layout->column($name) or panic $name;
        my $cell  = $self->cell($col);
        my $linked = $col->link_parent;

        my $cell_base
           = $cell->is_awaiting_approval ? $cell->old_values
           : $linked && $cell->old_values # linked, and value overwritten
           ? $cell->oldvalue
           : $cell;

        # Retain and provide recurse-prevention information. See further
        # comments in Linkspace::Column::Curcommon
        my $already_seen_code = $params{already_seen_code};
        $already_seen_code->{$col->id} = $params{level};

        $index{$name} = $cell_base->for_code(
           already_seen_code  => $already_seen_code,
           already_seen_level => $params{level} + ($col->is_curcommon ? 1 : 0),
        );
    };
    \%index;
}

# Initialise empty record for new write.
#XXX
sub initialise
{   my ($self, %options) = @_;

    my $all_columns = $self->sheet->layout->columns_search;
    $self->columns_retrieved_do($all_columns);

my $link_parent_row;
    my %cells;
    foreach my $column (@$all_columns)
    {   my $link_parent = $column->link_parent;
        $cells{$column->id}
           = $link_parent ? $link_parent_row->cell($link_parent)  #XXX
           : $column->class->new(
                record           => $self,
                record_id        => $self->record_id,
                column           => $column,
                layout           => $self->layout,
             );
    }
    $self->cells(\%cells);
}

sub approver_can_action_column
{   my ($self, $column) = @_;
    $column->user_can($self->approval_of_new ? 'approve_new' : 'approve_existing');
}

=head2 $data->blank_cells(@cols);
=cut

sub blank_cells(@)
{   my $self = shift;
    $self->cell($_)->set_value('') for @_;
}

sub write_linked_id
{   my ($self, $linked_id) = @_;

    my $sheet = $self->sheet;
    $sheet->user_can('link')
        or error __"You do not have permission to link records";

    my $guard = $::db->begin_work;
    if ($linked_id)
    {   # Blank existing values first, otherwise they will be read instead of
        # linked values under some circumstances
        $sheet->blank_cells(linked => 1);

        # There is some mileage in sending alerts here, but given that the
        # values are probably about to be updated with a linked value, there
        # seems little point
        $self->write(no_alerts => 1);
    }

    my $current = $::db->get_record(Current => $self->current_id);
    $current->update({ linked_id => $linked_id });
    $self->linked_id($linked_id);
    $guard->commit;
}

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

has _need_rec => (
    is        => 'rw',
    isa       => Bool,
    predicate => 1,
);

has _need_app => (
    is        => 'rw',
    isa       => Bool,
    predicate => 1,
);

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
my $sheet = $row->sheet;

    my $update_only = $self->sheet->forget_history || $args{update_only};

    # This will be called before a write for a normal edit, to allow checks on
    # next/prev values, but we call it here again now, for other writes that
    # haven't explicitly called it
    $self->set_blank_dependents;

    # First loop round: sanitise and see which if any have changed
    my %allow_update = map +($_ => 1), @{$args{allow_update} || []};
    my ($need_app, $need_rec, $child_unique); # Whether a new approval_rs or record_rs needs to be created
    $need_rec = 1 if $self->changed;

    # Whether any topics cannot be written because of missing cells in other topics.
    my %no_write_topics;
    my $cols = $args{submitted_cells}
       || $self->sheet->layout->columns_search(exclude_internal => 1);

    foreach my $column (grep $_->is_userinput, @$cols)
    {   my $datum = $self->cell($column)
            or next; # Will not be set for child records

        # Check for blank value
        if (   $datum->is_blank
            && (!$row->parent_row_id || $column->can_child)
            && !$row->linked_row_id
            && !$column->is_optional && !$args{force_mandatory}
            && !$args{draft}
            &&  $column->user_can('write')

            # Do not require value if the field has not been shown because of
            # display condition
            && $datum->dependent_shown
        )
        {
            if (my $topic = $column->topic && $column->topic->prevent_edit_topic)
            {   # This setting means that we can write this missing value, but we
                # will be unable to write another topic later
                my $t = $no_write_topics{$topic->id} ||= { topic => $topic };
                push @{$t->{columns}}, $column;
            }
            elsif($self->new_entry || $datum->changed)
            {   my $msg = __x"'{col.name}' is not optional. Please enter a value.", col => $column;
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
        if (     $column->isunique
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
        if ($self->parent_id && !$column->can_child && $column->userinput)
        {   # Calc values always unique
            my $parent = $self->parent->cell($column);
            $datum->set_value($parent->set_values, is_parent_value => 1);
        }

        if ($self->doing_approval)
        {   # See if the user has something that could be approved
            $need_rec = 1 if $self->approver_can_action_column($column);
        }
        elsif ($self->new_entry)
        {
            # New record. Approval needed?
            if($column->user_can('write_new_no_approval') || $args{draft})
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

    my $user_id = $self->user ? $self->user->id : undef;

    my $createdby = $args{version_userid} || $user_id;
    if($update_only)
    {
        # Keep original record values when only updating the record, except
        # when the update_only is happening for forgetting version history, in
        # which case we want to record these details
        $self->cell_update(_version_datetime => $created_date, is_parent_value => 1);
        $self->cell_update(_version_user => $createdby, no_validation => 1, is_parent_value => 1);
    }

    # Test duplicate unique calc values
    foreach my $column (@{$self->sheet->layout->columns})
    {
        next if !$column->has_cache || !$column->isunique;
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
    foreach my $topic (values %no_write_topics)
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
        $self->delete_user_drafts($sheet)
             unless $args{no_draft_delete};

        $current_id = $content->row_create({
            parent_id    => $self->parent_id,
            linked_id    => $self->linked_id,
            draftuser_id => $args{draft} && $user_id,
        });
    }

    if($need_rec && !$update_only)
    {    my $row = $self->create( {
            current_id => $current_id,
            created    => $created_date,
            createdby  => $createdby,
        });
        $self->record_id_old($self->record_id) if $self->record_id;
#XXX switch to $row
    }
    elsif ($self->sheet->forget_history)
    {   # All versions get new 'created'
        $::db->update(Record => $self->record_id, {
            created   => $created_date,
            createdby => $createdby,
        });
    }

    $self->cell_update(_id => $current_id);  #XXX prob not needed

    if ($need_app)
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
}

sub in_column_specific_tables($)
{   my ($self, $record_id) = @_;

    my $tables = Linkspace::Column->meta_tables;
    foreach my $table (@$tables)
    {   return 1 if $::db->search($table => { record_id => $record_id })->count;
    }
    0;
}

sub write_values
{   my ($self, %options) = @_;

    my $guard = $::db->begin_work;
    my $is_new = $self->new_entry;

    # Draft records may be incomplete
    my $is_draft = $options{is_draft};

    # Write all the values
    my %columns_changed = ($self->current_id => []);
    my (@columns_cached, %update_autocurs);

    my $approval_id = $self->approval_id;

    my $layout  = $self->sheet->layout;

    my $columns = $layout->columns_search(order_dependencies => 1, exclude_internal => 1);
    foreach my $column (@$columns)
    {
        # Prevent warnings when writing incomplete calc values on draft
        next if $is_draft && !$column->userinput;

        my $datum = $self->cell($column);
        next if $self->linked_id && $column->link_parent; # Don't write all values if this is a linked record

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
                  || !$column->userinput
            )
            {
                # Write new value
                $self->_cell_write($column, $datum, %options);

                push @{$columns_changed{$self->current_id}}, $column->id
                    if $datum->changed;
            }
            elsif($is_new)
            {   # Write value. It's a new entry and the user doesn't have
                # write access to this field. This will write a blank
                # value.
                $self->_cell_write($column, $datum) if !$column->userinput;
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

        if($self->_need_app)
        {   # Only need to write values that need approval
            next unless $datum->is_awaiting_approval;
            $self->_cell_write($column, $datum, approval => 1)
                if $is_new ? !$datum->is_blank : $datum->changed;
        }
    }

    # Test all internal columns for changes - these will not have been tested
    # during the write above
    my $internals = $self->sheet->layout->columns_search(only_internal => 1);
    foreach my $column (@$internals)
    {   push @{$columns_changed{$self->current_id}}, $column->id
            if $self->cell($column)->changed;
    }

    # If this is an approval, see if there is anything left to approve
    # in this record. If not, delete the stub record.
    if($self->doing_approval && ! $self->in_column_specific_tables($approval_id))
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
        my @columns = $self->layout->columns_search(order_dependencies => 1, exclude_internal => 1);

        foreach my $child (@{$self->row->child_rows})
        {   my @update;
            foreach my $col (@$columns)
            {   $col->is_userinput or next; # Calc/rag will be evaluated during update

                push @update, [ $col => $rev->cell($col)->values ]
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
    if (!$options{no_alerts} && !$options{draft})
    {
        # Possibly not the best way to do alerts, but certainly the
        # simplest. Spin up a new alert sender for each changed record
        foreach my $cid (keys %columns_changed)
        {
            my $alert_send = GADS::AlertSend->new(
                current_ids => [ $cid ],
                columns     => $columns_changed{$cid},
                current_new => $self->new_entry,
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

sub set_blank_dependents
{   my $self = shift;

    foreach my $column ($self->layout->columns_search(exclude_internal => 1))
    {   my $datum = $self->cell($column);
        $datum->set_value('')
            if ! $datum->dependent_shown
            && ($datum->column->can_child || !$self->parent_id);
    }
}

sub _cell_write
{   my ($self, $column, $datum, %options) = @_;

    $column->value_to_write
        or return;

    if ($column->userinput)
    {
        # No datum for new invisible cells
        my $child_unique = $datum ? $column->can_child : 0;

        my $layout_id    = $column->id;
        my $row_id       = $options{approval} ? $self->approval_id : $self->record_id;

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
            # Would be better to use find() here, but not all tables currently
            # have unique constraints. Also, we might want to add multiple values
            # for each field in the future.
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
    else
    {   $datum->record_id($self->record_id);
        $datum->re_evaluate;
        $datum->write_value;
    }
}

sub user_can_delete
{   my $self = shift;
    $self->current_id ? $self->sheet->user_can("delete") : 0;
}

sub delete_current
{   my ($self, $sheet, %options) = @_;
    my $cur_id = $self->current_id or return;

    my $current = $::db->search(Current => {
        id          => $cur_id,
        instance_id => $sheet->id,
    })->first
        or error "Unable to find current record to delete";

    $current->update({
        deleted   => DateTime->now,
        deletedby => $::session->user->id
    });
}

# Delete this this version completely from database
sub purge
{   my $self = shift;
    $self->sheet->user_can('purge')
        or error __"You do not have permission to purge records";

    $self->_purge_record_values($self->record_id);
    $::db->delete(Record => $self->record_id);
}

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
    foreach my $col (@$columns)
    {   my $short = $col->name_short or next;
        $return->{$short} = $self->cell($col)->as_string;
    }
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

    my $now = DateTime->now;
    $now->set_time_zone('Europe/London');

    my $pdf = CtrlO::PDF->new(
        footer => 'Downloaded by ' . $self->user->value . ' on '
                . $self->site->dt2local($now)." at ".$now->hms;
    );

    my $created = $self->created;
    my $updated = $self->site->dt2local($created)." at ".$created->hms;

    $pdf->add_page;
    $pdf->heading('Record '.$self->current_id);
    $pdf->heading('Last updated by '.$self->createdby->as_string." on $updated", size => 12);

    my @data    = [ 'Field', 'Value' ];
    my $columns = $self->sheet->layout->columns_search(user_can_read => 1);
    foreach my $col (@$columns)
    {   my $datum = $self->cell($col);
        $datum->dependent_shown or next;

        if ($col->is_curcommon)
        {   my $th   = $col->name;
            foreach my $line (@{$datum->values})
            {   my @td = map $_->as_string, @{$line->{values}};
                push @data, [ $th, @td ];
                $th    = '';
            }
        }
        else {
        {   push @data, [ $col->name, $datum->as_string ];
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
    {
        my $has = @$d;
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

#XXX I have seen similar lists on other places
my @purge_tables = qw/Ragval Calcval Enum String Intgr Daterange Date Person File Curval/;

sub _revision_delete
{   my ($self, $rid) = @_;

    my $which = +{ record_id => $rid };
    $::db->delete($_ => $which) for @purge_tables;

    $self->user->row_remove_cursors($rid);
}

sub revision_count($)
{   my ($thing, $sheet) = @_;
    $::db->search(Record => { sheet => $sheet }, { join => 'current' })->count;
}

#----------------------
=head1 METHODS: Submission token
=cut

sub create_submission_token
{   my $self = shift;
    for (1..10)
    {   # Prevent infinite loops in case something is really wrong with the
        # system (token collisions are implausible)
        my $token = Session::Token->new(length => 32)->get;
        try { $::db->create(Submission => {
                created => DateTime->now,
                token   => $token,
            });
        };
        return $token unless $@;
    }
    undef;
}

sub consume_submission_token($)
{   my ($class, $token) = @_;
    my $sub = $::db->search(Submission => {token => $token})->first;
    $sub or reteurn;  # Should always be found, but who knows

    # The submission table has a unique constraint on the token and
    # submitted cells. If we have already been submitted, then we
    # won't be able to write a new submitted version of this token, and
    # the record insert will therefore fail.
    try {
        $::db->create(Submission => {
            token     => $token,
            created   => DateTime->now,
            submitted => 1,
        });
    };

    if($@)
    {   # borked, assume that the token has already been submitted
        error __"This form has already been submitted and is currently being processed";
    }
}

1;
