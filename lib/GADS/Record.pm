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

# 'fields' are datum objects, for each column in a row (record)
# each 'column' object describes the datum objects in a column
package GADS::Record;

use CtrlO::PDF;
use DateTime;
use DateTime::Format::Strptime qw( );
use Log::Report 'linkspace';
use JSON qw(encode_json);
use PDF::Table 0.11.0; # Needed for colspan feature
use Scope::Guard qw(guard);
use Session::Token;
use URI::Escape;
use Scalar::Util  qw(blessed);

use GADS::AlertSend;
use GADS::Datum::Tree;
use Linkspace::Sheet::Layout;

use Linkspace::Util qw(index_by_id);

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
use MooX::Types::MooseLike::DateTime qw/DateAndTime/;
use namespace::clean;

with 'GADS::Role::Presentation::Record';

# The raw parent linked record from the database, if applicable
has linked_record_raw => (
    is      => 'rw',
);

# The parent linked record as a GADS::Record object
has linked_record => (
    is => 'lazy',
);

sub has_rag_column()
{   !! first { $_->type eq 'rag' } @{$self->columns_view};
}

sub _sibling_record(%) {
    my ($self, %sibling) = @_;
    $sibling{user}   //= $self->user;
    $sibling{layout} //= $self->layout;
    (ref $self)->new(%sibling);
}

sub _build_linked_record
{   my $self = shift;
    my $linked = $self->_sibling_record;
    $linked->find_current_id($self->linked_id);
    $linked;
}

has set_record_created => (
    is      => 'rw',
);

has set_record_created_user => (
    is      => 'rw',
);

has curcommon_all_fields => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

# Should be set true if we are processing an approval
has doing_approval => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has columns => (
    is      => 'rw',
    isa     => ArrayRef,
);

sub has_fields
{   my ($self, $field_ids) = @_;
    foreach my $id (@$field_ids)
    {   return 0 if !$self->_columns_retrieved_index->{$id};
    }
    return 1;
}

has is_group => (
    is => 'ro',
);

has group_cols => (
    is => 'ro',
);

has id_count => (
    is      => 'rwp',
);

has _columns_retrieved_index => (
    is  => 'lazy',
    builder = sub { index_by_id $_[0]->columns_retrieved_do },
);

# XXX Can we not reference the parent Records entry somehow
# or vice-versa?
# Value containing the actual columns retrieved.
# In "normal order" as per layout.
has columns_retrieved_no => (
    is => 'rw',
);

# Value containing the actual columns retrieved.
# In "dependent order", needed for calcvals
has columns_retrieved_do => (
    is => 'rw',
);

# Same as GADS::Records property
has columns_view => (
    is => 'rw',
);

# Whether this is a new record, not yet in the database
has new_entry => (
    is      => 'ro',
    isa     => Bool,
    lazy    => 1,
    clearer => 1,
    builder => sub { !$_[0]->current_id },
);

has record_id => (
    is      => 'rw',
    lazy    => 1,
    builder => sub {
        my $self = shift;
        $self->_set_record_id($self->record);
    },
);

has record_id_old => (
    is => 'rw',
);

# The ID of the parent record that this is related to, in the
# case of a linked record
has linked_id => (
    is      => 'rw',
    isa     => Maybe[Int],
    lazy    => 1,
    coerce  => sub { $_[0] || undef }, # empty string from form submit
    builder => sub {
        my $self = shift;
        my $cid     = $self->current_id or return;
        my $current = $::db->get_record(Current => $cid);
        $current ? $current->linked_id : undef;
    },
);

sub forget_history { $_[0]->sheet->forget_history }

# The ID of the parent record that this is a child to, in the
# case of a child record
# from base-class parent_id

has parent => (
    is      => 'lazy',
    builder => sub { $_[0]->sheet->data->row($_[0]->parent_id) },
);

has child_record_ids => (
    is      => 'rwp',
    isa     => ArrayRef,
    lazy    => 1,
    builder => sub {
        my $self = shift;
        return [] if $self->parent_id;

        my $children = $::db->search(Current => {
            parent_id         => $self->current_id,
            'me.deleted'      => undef,
            'me.draftuser_id' => undef,
        });

        [ $children->get_column('id')->all ];
    },
);

has serial => (
    is  => 'lazy',
    isa => Maybe[Int],
    builder => sub {
        my $cid = shift->current_id;
        $::db->get_record(Current => $cid)->serial;
    },
}

has is_draft => (
    is      => 'lazy',
    isa     => Bool,
    coerce  => sub { $_[0] ? 1 : 0 }, # Allow direct passing of draftuser_id
);

sub _build_is_draft
{   my $self = shift;
    return !!$self->{record}->{draftuser_id}
        if exists $self->{record}->{draftuser_id};

    return if $self->new_entry;
    !! $::db->get_record(Current => $self->current_id)->draftuser_id;
}

has approval_id => (
    is => 'rw',
);

# Whether this is an approval record for a new entry.
# Used when checking permissions for approving
has approval_of_new => (
    is      => 'lazy',
    isa     => Bool,
);

# Whether to initialise fields that have no value
has init_no_value => (
    is      => 'rw',
    isa     => Bool,
    default => 1,
);

# Whether this is a record for approval
has approval_flag => (
    is  => 'rwp',
    isa => Bool,
);

# The associated record if this is a record for approval
has approval_record_id => (
    is  => 'rwp',
    isa => Maybe[Int],
);

has include_approval => (
    is => 'rw',
);

# A way of forcing the write function to know that this record
# has changed. For example, if removing a field from a child
# record, which would otherwise go unnoticed
has changed => (
    is      => 'rw',
    isa     => Bool,
    default => 0,
);

# Whether the record has changed (i.e. if any fields have changed). This only
# includes fields that are input as a user, as a record will often have a value
# changed just by performing an edit (e.g. last edited time)
sub is_edited
{   my $self = shift;
    !! grep $_->changed && grep $_->column->userinput,
         values %{$self->fields};
}

has current_id => (
    is      => 'rw',
    isa     => Maybe[Int],
    lazy    => 1,
    coerce  => sub { defined $_[0] ? int $_[0] : undef }, # Ensure integer for JSON encoding
    builder => sub {
        my $self = shift;
        $self->record or return undef;
        $self->record->{current_id};
    },
);

has fields => (
    is      => 'rw',
    lazy    => 1,
    builder => sub {
        my $self = shift;
        $self->_transform_values;
    },
);

sub field($)
{   my ($self, $col) = @_;

    my $fields = $self->fields;
    return $fields->{$col->id} # ::Column object
        if blessed $col;

    return $fields->{$col}     # numeric
        if $col !~ /\D/;

    my $c = $self->layout->column_by_name_short($col)
         || $self->layout->column_by_name($col);

    $c ? $fields->{$col->id} : undef;
}

has createdby => (
    is      => 'rw',
    lazy    => 1,
    builder => sub {
        my $self = shift;
        return undef if $self->new_entry;

        return $self->field('_version_user')
            if $self->record;

        my $creator = $::db->get_record(Record => $self->record_id)->createdby;
        $self->_person({ id => $creator->id }, '_version_user');
    },
);

has set_deletedby => (
    is      => 'rw',
    trigger => sub { shift->clear_deletedby },
);

has deletedby => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
        my $self = shift;
        # Don't try and build if we are a new entry. By the time this is called,
        # the current ID may have been removed from the database due to a rollback
        return if $self->new_entry;

        if(!$self->record)
        {   $self->record_id or return;
            my $user = $::db->get_record(Record => $self->record_id)->deletedby
                or return undef;
            return $self->_person({ id => $user->id }, '_deleted_by');
        }

        my $value = $self->set_deletedby or return undef;
        $self->_person($value, '_deleted_by');
    },
);

sub _person
{   my ($self, $value, $column_name) = @_;
    my $column = $self->layout->column_by_name_short($column_name);
    GADS::Datum::Person->new(
        record           => $self,
        record_id        => $self->record_id,
        current_id       => $self->current_id,
        column           => $column,
        layout           => $self->layout,
        init_value       => $value,
    );
}

has created => (
    is      => 'lazy',
    isa     => DateAndTime,
);

sub _build_created
{   my $self   = shift;
    my $record = $self->record
        or return $::db->get_record(Record => $self->record_id)->created;

    $::db->parse_datetime($record->{created});
}

has set_deleted => (
    is      => 'rw',
    trigger => sub { shift->clear_deleted },
);

has deleted => (
    is      => 'lazy',
    isa     => Maybe[DateAndTime],
);

sub _build_deleted
{   my $self = shift;
    # Don't try and build if we are a new entry. By the time this is called,
    # the current ID may have been removed from the database due to a rollback
    return if $self->new_entry;
    if (!$self->record)
    {   $self->current_id or return;
        return $::db->get_record(Record => $self->record_id)->deleted;
    }

    $::db->parse_datetime($self->set_deleted);
}

# Whether to take results from some previous point in time
has rewind => (
    is  => 'ro',
    isa => Maybe[DateAndTime],
);

has is_historic => (
    is      => 'lazy',
    isa     => Bool,
);

sub _build_approval_of_new
{   my $self = shift;
    # record_id could either be an approval record itself, or
    # a record. If it's an approval record, get its record
    my $record_id = $self->approval_id || $self->record_id;

    my $record = $self->schema->resultset('Record')->find($record_id);
    $record = $record->record if $record->record; # Approval
    $::db->search(Record => {
        'me.id'              => $record->id,
        'record_previous.id' => undef,
    },{
        join => 'record_previous',
    })->count;
}

sub _build_is_historic
{   my $self = shift;
    my $current_rec_id = $self->record->{current}->{record_id};
    $current_rec_id && $current_rec_id != $self->record_id;
}

# Remove IDs from record, to effectively make this a new unwritten
# record. Used when prefilling values.
sub remove_id
{   my $self = shift;
    $self->current_id(undef);
    $self->linked_id(undef);
    $self->clear_new_entry;
}

sub find_record_id
{   my ($self, $record_id, %options) = @_;
    my $search_instance_id = $options{instance_id};

    my $record = $::db->get_record(Record => $record_id)
        or error __x"Record version ID {id} not found", id => $record_id;

    my $instance_id = $record->current->instance_id;  #XXX id as table name?
    error __x"Record ID {id} invalid for table {table}", id => $record_id, table => $search_instance_id
        if $search_instance_id && $search_instance_id != $instance_id;

    $self->_set_instance_id($instance_id);
    $self->_find(record_id => $record_id, %options);
}

sub find_current_id
{   my ($self, $current_id, %options) = @_;
    my $search_instance_id = $options{instance_id};

    $current_id or return;
    $current_id =~ /^[0-9]+$/
        or error __x"Invalid record ID {id}", id => $current_id;

    my $current = $::db->get_record(Current => $current_id)
        or error __x"Record ID {id} not found", id => $current_id;

    !$search_instance_id || $search_instance_id == $current->instance_id
        or error __x"Record ID {id} invalid for table {table}",
            id => $current_id, table => $search_instance_id;

    $self->_set_instance_id($current->instance_id);
    $self->_find(current_id => $current_id, %options);
}

sub find_draftuser
{   my ($self, $user, %options) = @_;
    my $user_id = blessed $user ? $user->id : $user;
    $user_id =~ /^[0-9]+$/
        or error __x"Invalid draft user ID {id}", id => $user_id;

    $self->_set_instance_id($options{instance_id})
        if $options{instance_id};

    # Don't normally want to throw fatal errors if a draft does not exist
    $self->_find(draftuser_id => $user_id, no_errors => 1, %options);
}

sub find_serial_id
{   my ($self, $serial_id) = @_;
    return unless $serial_id;
    $serial_id =~ /^[0-9]+$/
        or error __x"Invalid serial ID {id}", id => $serial_id;

    my $current = $::db->search(Current => {
        serial      => $serial_id,
        instance_id => $self->sheet->id,
    })->first
        or error __x"Serial ID {id} not found", id => $serial_id;

    $self->_seed_layout($self->layout);
    $self->_find(current_id => $current->id);
}

sub find_deleted_currentid
{   my ($self, $current_id) = @_;
    $self->find_current_id($current_id, deleted => 1)
}

sub find_deleted_recordid
{   my ($self, $record_id) = @_;
    $self->find_record_id($record_id, deleted => 1)
}

# Returns new GADS::Record object, doesn't change current one
sub find_unique
{   my ($self, $column, $value, $retrieve_columns) = @_;

    return $self->find_current_id($value)
        if $column->id == $self->layout->column_id;

    my $serial_col = $self->layout->column_by_name_short('_serial');
    return $self->find_serial_id($value)
        if $column->id == $serial_col->id;

    # First create a view to search for this value in the column.
    my $filter = encode_json({
        rules => [{
            field       => $column->id,
            id          => $column->id,
            type        => $column->type,
            value       => $value,
            value_field => $column->value_field_as_index($value),
            operator    => 'equal',
        }]
    });
    my $view = GADS::View->new(
        filter      => $filter,
        instance_id => $self->layout->instance_id,
        layout      => $self->layout,
        user        => undef,
    );
    $retrieve_columns = [ $column->id ]
        unless @$retrieve_columns;

    my $records = GADS::Records->new(
        user    => undef, # Do not want to limit by user
        rows    => 1,
        view    => $view,
        layout  => $self->layout,
        columns => $retrieve_columns,
    );

    # Might be more, but one will do
    pop @{$records->results};
}

# XXX This whole section is getting messy and duplicating a lot of code from
# GADS::Records. Ideally this needs to share the same code.
sub _find
{   my ($self, %find) = @_;

    # First clear applicable properties
    $self->clear;

    # If deleted, make sure user has access to purged records
    error __"You do not have access to this deleted record"
        if $find{deleted} && !$self->layout->user_can("purge");

    my $is_draft = !! $find{draftuser_id};
    my $record_id = $find{record_id};

    my $records = GADS::Records->new(
        curcommon_all_fields => $self->curcommon_all_fields,
        layout               => $self->layout,
        columns              => $self->columns,
        rewind               => $self->rewind,
        is_deleted           => $find{deleted},
        is_draft             => $is_dragt || $find{include_draft} ? 1 : 0,
        no_view_limits       => $is_draft,
        include_approval     => $self->include_approval,
        include_children     => 1,
        view_limit_extra_id  => undef, # Remove any default extra view
    );

    $self->columns_retrieved_do($records->columns_retrieved_do);
    $self->columns_retrieved_no($records->columns_retrieved_no);
    $self->columns_view($records->columns_view);

    my $record = {}; my $limit = 10; my $page = 1; my $first_run = 1;
    while (1)
    {
        # No linked here so that we get the ones needed in accordance with this loop (could be either)
        my @prefetches = $records->jpfetch(prefetch => 1, search => 1, limit => $limit, page => $page); # Still need search in case of view limit
        last if !@prefetches && !$first_run;
        my $search     = $find{current_id} || $find{draftuser_id}
            ? $records->search_query(prefetch => 1, linked => 1, limit => $limit, page => $page)
            : $records->search_query(root_table => 'record', prefetch => 1, linked => 1, limit => $limit, no_current => 1, page => $page);
        @prefetches = $records->jpfetch(prefetch => 1, search => 1, linked => 0, limit => $limit, page => $page); # Still need search in case of view limit


        my $root_table;
        if($record_id)
        {
            unshift @prefetches, (
                {
                    current => [
                        'deletedby',
                        $records->linked_hash(prefetch => 1, limit => $limit, page => $page),
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
                $records->linked_hash(prefetch => 1, limit => $limit, page => $page),
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

        local $GADS::Schema::Result::Record::REWIND = $records->rewind_formatted
            if $records->rewind;

        # Don't specify linked for fetching columns, we will get whatever is needed linked or not linked
        my @columns_fetch = $records->columns_fetch(search => 1, limit => $limit, page => $page); # Still need search in case of view limit
        my $has_linked = $records->has_linked(prefetch => 1, limit => $limit, page => $page);

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
        # values for single fields are retrieved separately. However, if a
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
                {   my @existing = grep $_->{id},
                        ref $has eq 'ARRAY' ? @$has : $has;

                    push @existing, $rec->{$key}
                        if ! grep $rec->{$key}->{id} == $_->{id}, @existing;
                    $record->{$key} = \@existing;
                }
                else {
                    $record->{$key} = $rec->{$key};
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

    # Find the user that created this record. XXX Ideally this would be done as
    # part of the original query, as it is for GADS::Records. See comment above
    # about this function
    my $first = $::db->search(Record => {
        current_id => $record->{current_id}
    })->get_column('id')->min;

    my $creator = $::db->get_record(Record => $first)->createdby;
    $self->set_record_created_user({$creator->get_columns})
        if $creator;

    # Fetch and merge and multi-values
    my @record_ids = ($record->{id});
    push @record_ids, $record->{linked}->{record_id}
        if $record->{linked} && $record->{linked}->{record_id};

    # Related record if this is approval record
    $self->_set_approval_record_id($record->{record_id})
        if $self->_set_approval_flag($record->{approval});

    $self->record($record);

    # Fetch and add multi-values
    $records->fetch_multivalues(
        record_ids           => \@record_ids,
        retrieved            => [ $record ],
        records              => [ $self ],    #XXX refref?
        is_draft             => $find{draftuser_id},
        curcommon_all_fields => $self->curcommon_all_fields,
    );

    $self; # Allow chaining
}

sub clone
{   my $self = shift;
    my $cloned = $self->_sibling_record;

    my %fields;
    $fields{$_} = $self->field($_)->clone(fresh => 1, record => $cloned, current_id => undef, record_id => undef)
        for keys %{$self->fields};

    $cloned->fields(\%fields);
    $cloned;
}

sub load_remembered_values
{   my ($self, %options) = @_;
    my $user = $::session->user;

    # First see if there's a draft. If so, use that instead
    if ($user->has_draft($self->sheet)
    {
        $self->_set_instance_id($self->layout->instance_id)
            if !$options{instance_id};

        if($self->find_draftuser($user))
        {   $self->remove_id;
            return;
        }
        $self->initialise;
    }

    my @remember = map $_->id, $sheet->layout->columns_search(remember => 1);
    @remember or return;

    my $lastrecord = $::db->search(UserLastrecord => {
        'me.instance_id'  => $sheet->id,
        user_id           => $user->id,
        'current.deleted' => undef,
    },{
        join => { record => 'current' },
    })->next
        or return;

    my $previous = $self->_sibling_record;
    $previous->columns(\@remember);
    $previous->include_approval(1);
    $previous->find_record_id($lastrecord->record_id);

    # Use the column object from the current record not the "previous" record,
    # as otherwise the column's layout object goes out of scope and is not
    # available due to its weakref
    $self->field($_) = $previous->field($_)->clone(record => $self, column => $self->layout->column($_->id))
        for @{$previous->columns_retrieved_do};

    if ($previous->approval_flag)
    {
        # The last edited record was one for approval. This will
        # be missing values, so get its associated main record,
        # and use the values for that too.
        # There will only be an associated main record if some
        # values did not need approval
        if ($previous->approval_record_id)
        {
            my $child = $self->_sibling_record(include_approval => 1);
            $child->find_record_id($self->approval_record_id);

            my $fields = $self->fields;
            foreach my $col ($sheet->layout->columns_search(user_can_write_new => 1, userinput => 1))
            {
                # See if the record above had a value. If not, fill with the
                # approval record's value
                my $field = $self->field($col);
                $fields->{$col->id} = $field->clone(record => $self)
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
{   my $self = shift;

    my $original = $self->record or panic "Record data has not been set";

    my $fields = {};
    # If any columns are multivalue, then the values will not have been
    # prefetched, as prefetching can result in an exponential amount of
    # rows being fetched from the database in one go. It's better to pull
    # all types of value together though, so we store them in this hashref.
    my $multi_values = {};
    # We must do these columns in dependent order, otherwise the
    # column values may not exist for the calc values.
    foreach my $column (@{$self->columns_retrieved_do})
    {   next if $column->is_internal;

        my $key = ($self->linked_id && $column->link_parent ? $column->link_parent : $column)->field;
        # If this value was retrieved as part of a grouping, and if it's a sum,
        # then the field key will be appended with "_sum". XXX Ideally we'd
        # have a better way of knowing this has happened, but this should
        # suffice for the moment.
        if ($self->is_group)
        {
            if ($column->is_numeric)
            {   $key = $key."_sum";
            }
            elsif(!$self->group_cols->{$column->id})
            {   $key = $key."_distinct";
            }
        }

        #XXX $original in either case
        my $value = $self->linked_id && $column->link_parent ? $original->{$key} : $original->{$key};
        $value = $self->linked_record_raw && $self->linked_record_raw->{$key}
            if $self->linked_record_raw && $column->link_parent && !$self->is_historic;

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
        # For curcommon fields, flag that this field has had all its columns if
        # that is what has happened. Then we know during any later process of
        # this column that there is no need to retrieve any other columns
        $column->retrieve_all_columns(1)
            if $self->curcommon_all_fields && $column->is_curcommon;
        my $class = $self->is_group && !$column->is_numeric && !$self->group_cols->{$column->id}
            ? 'GADS::Datum::Count'
            : $column->class;

        $fields->{$column->id} = $class->new(%params);
    }

    $self->_set_id_count($original->{id_count});

    my $column_id = $self->layout->column_id;
    $fields->{$column_id->id} = GADS::Datum::ID->new(
        record           => $self,
        record_id        => $self->record_id,
        current_id       => $self->current_id,
        column           => $column_id,
        layout           => $self->layout,
    );
    my $created = $self->layout->column_by_name_short('_version_datetime');
    $fields->{$created->id} = GADS::Datum::Date->new(
        record           => $self,
        record_id        => $self->record_id,
        current_id       => $self->current_id,
        column           => $created,
        layout           => $self->layout,
        init_value       => [ { value => $original->{created} } ],
    );

    my $version_user_col = $self->layout->column_by_name_short('_version_user');
    my $version_user_val = $original->{createdby} || $original->{$version_user_col->field};
    $fields->{$version_user_col->id} = $self->_person($version_user_val, '_version_user');

    my $createdby_col = $self->layout->column_by_name_short('_created_user');
    my $created_val = $self->set_record_created_user;
    if (!$created_val) # Single record retrieval does not set this
    {
        my $created_val_id = $::db->search(Record => {
            current_id => $self->current_id,
        })->get_column('created')->min;
    }
    $fields->{$createdby_col->id} = $self->_person($created_val, '_created_user');

    my $record_created_col = $self->layout->column_by_name_short('_created');
    my $record_created = $self->set_record_created;
    if (!$record_created) # Single record retrieval does not set this
    {
        $record_created = $::db->search(Record => {
            current_id => $self->current_id,
        })->get_column('created')->min;
    }

    $fields->{$record_created_col->id} = GADS::Datum::Date->new(
        record           => $self,
        record_id        => $self->record_id,
        current_id       => $self->current_id,
        column           => $record_created_col,
        layout           => $self->layout,
        init_value       => [ { value => $record_created } ],
    );

    my $serial_col = $self->layout->column_by_name_short('_serial');
    $fields->{$serial_col->id} = GADS::Datum::Serial->new(
        record           => $self,
        value            => $self->serial,
        record_id        => $self->record_id,
        current_id       => $self->current_id,
        column           => $serial_col,
        layout           => $self->layout,
    );
    $fields;
}

sub values_by_shortname
{   my ($self, %params) = @_;
    my $names = $params{names};

    my %index;
    foreach my $name (@$names)
    {   my $col    = $self->layout->column_by_name_short($name)
            or error __x"Short name {name} does not exist", name => $name;

        my $linked = $self->linked_id && $col->link_parent;
        my $datum  = $self->field($col)
            or panic __x"Value for column {name} missing. Possibly missing entry in layout_depend?", name => $col->name;

        my $d = $datum->is_awaiting_approval
            ? $datum->oldvalue
            : $linked && $datum->oldvalue # linked, and value overwritten
            ? $datum->oldvalue
            : $datum;

        # Retain and provide recurse-prevention information. See further
        # comments in Linspace::Column::Curcommon
        my $already_seen_code = $params{already_seen_code};
        $already_seen_code->{$col->id} = $params{level};
        $d->already_seen_code($already_seen_code);
        $d->already_seen_level($params{level} + ($col->is_curcommon ? 1 : 0));
        $index{$name} = $d->for_code;
    };
    \%index;
}

# Initialise empty record for new write.
#XXX
sub initialise
{   my ($self, %options) = @_;

    my $all_columns = $self->sheet->layout->columns_search(include_internal => 1);
    $self->columns_retrieved_do($all_columns);

    my %fields;
    foreach my $column (@$all_columns)
    {   $fields{$column->id}
           = $self->linked_id && $column->link_parent
           ? $self->linked_record->field($column->link_parent)
           : $column->class->new(
                record           => $self,
                record_id        => $self->record_id,
                column           => $column,
                layout           => $self->layout,
             );
    }
    $self->fields(\%fields);
}

sub approver_can_action_column
{   my ($self, $column) = @_;
    $column->user_can($self->approval_of_new ? 'approve_new' : 'approve_existing');
}

=head2 $data->blank_fields(@cols);
=cut

sub blank_fields(@)
{   my $self = shift;
    $self->field($_)->set_value('') for @cols;
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
        $sheet->blank_fields(linked => 1);

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
        my @curval = map $draft->field($_),
            grep $_->type eq 'curval', $draft->columns;

        $draft->delete_current($sheet);
        $draft->purge_current;
        $_->purge_drafts for @curval;
    }
}

sub create_submission_token
{   my $self = shift;
    return undef if !$self->new_entry;
    for (1..10) # Prevent infinite loops - highly unlikely to be more than 10 clashes
    {
        my $token = Session::Token->new(length => 32)->get;
        try { # will bork on duplicate
            $::db->create(Submission => {
                created => DateTime->now,
                token   => $token,
            });
        };
        return $token unless $@;
    }
    return undef;
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


has already_submitted_error => (
    is      => 'rwp',
    isa     => Bool,
    default => 0,
);

# options (mostly used by onboard):
# - update_only: update the values of the existing record instead of creating a
# new version. This allows updates that aren't recorded in the history, and
# allows the correcting of previous versions that have since been changed.
# - force_mandatory: allow blank mandatory values
# - no_change_unless_blank: bork on updates to existing values unless blank
# - dry_run: do not actually perform any writes, test only
# - no_alerts: do not send any alerts for changed values
# - version_datetime: write version date as this instead of now
# - version_userid: user ID for this version if override required
# - missing_not_fatal: whether missing mandatory values are not fatal (but still reported)
# - submitted_fields: an array ref of the fields to check on initial
#   submission. Fields not contained in here will not be checked for missing
#   values. Used in conjunction with missing_not_fatal to only report on some
#   fields
sub write
{   my ($self, %options) = @_;

    # First check the submission token to see if this has already been
    # submitted. Do this as quickly as possible to prevent chance of 2 very
    # quick submissions, and do it before the guard so that the submitted token
    # is visible as quickly as possible
    if ($options{submission_token} && $self->new_entry)
    {
        my $sub = $::db->search(Submission => {
            token => $options{submission_token},
        })->first;

        if ($sub) # Should always be found, but who knows
        {
            # The submission table has a unique constraint on the token and
            # submitted fields. If we have already been submitted, then we
            # won't be able to write a new submitted version of this token, and
            # the record insert will therefore fail.
            try {
                $::db->create(Submission => {
                    token     => $sub->token,
                    created   => DateTime->now,
                    submitted => 1,
                });
            };

            if($@)
            {   # borked, assume that the token has already been submitted
                $self->_set_already_submitted_error(1);
                error __"This form has already been submitted and is currently being processed";
            }

            # Normally all write options are passed to further writes within
            # this call. Don't pass the submission token though, otherwise it
            # will bork as having already been used
            delete $options{submission_token};
        }
    }

    # See whether this instance is set to not record history. If so, override
    # update_only option to ensure it is only an update
    $options{update_only} = 1 if $self->forget_history;

    ! $options{draft} || $self->new_entry
        or error __"Cannot save draft of existing record";

    my $guard = $::db->begin_work;

    # Create a new overall record if it's new, otherwise
    # load the old values
    ! $self->new_entry || $self->layout->user_can('write_new')
        or error __"No permissions to add a new entry";

    if(my $pid = $self->parent_id)
    {   # Check whether this is an attempt to create a child of a child record
        error __"Cannot create a child record for an existing child record"
            if $::db->search(Current => {
                id        => $pid
                parent_id => { '!=' => undef },
            })->count;
    }

    # Don't allow editing rewind record - would cause unexpected things with
    # things such as "changed" tests
    ! $self->rewind
        or error __"Unable to edit record that has been retrieved with rewind";

    # This will be called before a write for a normal edit, to allow checks on
    # next/prev values, but we call it here again now, for other writes that
    # haven't explicitly called it
    $self->set_blank_dependents;

    # First loop round: sanitise and see which if any have changed
    my %allow_update = map { $_ => 1 } @{$options{allow_update} || []};
    my ($need_app, $need_rec, $child_unique); # Whether a new approval_rs or record_rs needs to be created
    $need_rec = 1 if $self->changed;

    # Whether any topics cannot be written because of missing fields in
    # other topics
    my %no_write_topics;
    my $cols = $options{submitted_fields}
       || $self->sheet->layout->columns_search(exclude_internal => 1);

    foreach my $column (grep $_->userinput, @$cols)
    {   my $datum = $self->field($column)
            or next; # Will not be set for child records

        # Check for blank value
        if (
               (!$self->parent_id || $column->can_child)
            && !$self->linked_id
            && !$column->is_optional
            &&  $datum->is_blank
            && !$options{force_mandatory}
            && !$options{draft}
            &&  $column->user_can('write')
        )
        {
            # Do not require value if the field has not been showed because of
            # display condition
            if($datum->dependent_shown)
            {
                if (my $topic = $column->topic && $column->topic->prevent_edit_topic)
                {
                    # This setting means that we can write this missing
                    # value, but we will be unable to write another topic
                    # later
                    $no_write_topics{$topic->id} ||= { topic => $topic, columns => [] };
                    push @{$no_write_topics{$topic->id}{columns}}, $column;
                }
                else {
                    # Only warn if it was previously blank, otherwise it might
                    # be a read-only field for this user
                    if (!$self->new_entry && !$datum->changed)
                    {
                        mistake __x"'{col}' is no longer optional, but was previously blank for this record.", col => $column->{name};
                    }
                    else {
                        my $msg = __x"'{col}' is not optional. Please enter a value.", col => $column->name;
                        error $msg
                            unless $options{missing_not_fatal};
                        report { is_fatal => 0 }, ERROR => $msg;
                    }
                }
            }
        }

        if ($self->doing_approval && $self->approval_of_new)
        {
            error __x"You do not have permission to approve new values of new records"
                if $datum->changed && !$column->user_can('approve_new');
        }
        elsif ($self->doing_approval)
        {
            error __x"You do not have permission to approve edits of existing records"
                if $datum->changed && !$column->user_can('approve_existing');
        }
        elsif ($self->new_entry)
        {
            error __x"You do not have permission to add data to field {name}", name => $column->name
                if !$datum->is_blank && !$column->user_can('write_new');
        }
        elsif ($datum->changed && !$column->user_can('write_existing'))
        {
            # If the user does not have write access to the field, but has
            # permission to create child records, then we want to allow them
            # to add a blank field to the child record. If they do, they
            # will land here, so we check for that and only error if they
            # have entered a value.
            if ($datum->is_blank && $self->parent_id)
            {
                # Force new record to write if this is the only change
                $need_rec = 1;
            }
            else
            {   error __x"You do not have permission to edit field {name}", name => $column->name;
            }
        }

        #  Check for no change option, used by onboarding script
        if ($options{no_change_unless_blank} && !$self->new_entry && $datum->changed && !$datum->oldvalue->is_blank)
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
            my $parent = $self->parent->field($column);
            $datum->set_value($parent->set_values, is_parent_value => 1);
        }

        if ($self->doing_approval)
        {   # See if the user has something that could be approved
            $need_rec = 1 if $self->approver_can_action_column($column);
        }
        elsif ($self->new_entry)
        {
            # New record. Approval needed?
            if ($column->user_can('write_new_no_approval') || $options{draft})
            {
                # User has permission to not need approval
                $need_rec = 1;
            }
            elsif ($column->user_can('write_new')) {
                # This needs an approval record
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

    my $created_date = $options{version_datetime} || DateTime->now;

    $self->field('_created')->set_value($created_date, is_parent_value => 1)
        if $self->new_entry;

    my $user_id = $self->user ? $self->user->id : undef;

    my $createdby = $options{version_userid} || $user_id;
    if (!$options{update_only} || $self->forget_history)
    {
        # Keep original record values when only updating the record, except
        # when the update_only is happening for forgetting version history, in
        # which case we want to record these details
        $self->field('_version_datetime')
             ->set_value($created_date, is_parent_value => 1);

        $self->field('_version_user')
             ->set_value($createdby, no_validation => 1, is_parent_value => 1);
    }

    # Test duplicate unique calc values
    foreach my $column (@{$self->sheet->layout->columns})
    {
        next if !$column->has_cache || !$column->isunique;
        my $datum = $self->field($column);
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
        foreach my $col ($topic->{topic}->fields)
        {
            error __x"You cannot write to {col} until the following fields have been completed: {fields}",
                col => $col->name, fields => [ map $_->name, @{$topic->{columns}} ]
                    if ! $self->field($col)->is_blank;
        }
    }

    # Error if child record as no fields selected
    error __"There are no child fields defined to be able to create a child record"
        if $self->parent_id && !$child_unique && $self->new_entry;

    # Anything to update?
    if(   !($need_app || $need_rec || $options{update_only})
       || $options{dry_run} )
    {   $guard->commit;  # commit nothing, just finish guard
        return;
    }

    # New record?
    if ($self->new_entry)
    {
        $self->delete_user_drafts($sheet)
             unless $options{no_draft_delete}; # Delete any drafts first, for both draft save and full save

        my $instance_id = $self->layout->instance_id;
        my $current = $::db->create(Current => {
            parent_id    => $self->parent_id,
            linked_id    => $self->linked_id,
            instance_id  => $sheet->id,
            draftuser_id => $options{draft} && $user_id,
        });

        # Create unique serial. This should normally only take one attempt, but
        # if multiple records are being written concurrently, then the unique
        # constraint on the serial column will fail on a duplicate. In that
        # case, roll back to the save point and try again.
        while (1)
        {
            last if $options{draft};
            my $serial = $::db->search(Current => {
                instance_id => $sheet->id,
            })->get_column('serial')->max;
            $serial++;

            my $svp = $self->schema->storage->svp_begin;
            try {
                $current->update({ serial => $serial });
            };
            if ($@) {
                $::db->schema->storage->svp_rollback;
            }
            else {
                $::db->schema->storage->svp_release;
                last;
            }
        }

        $self->current_id($current->id);
    }

    if ($need_rec && !$options{update_only})
    {
        my $id = $::db->create(Record => {
            current_id => $self->current_id,
            created    => $created_date,
            createdby  => $createdby,
        })->id;
        $self->record_id_old($self->record_id) if $self->record_id;
        $self->record_id($id);
    }
    elsif ($self->forget_history)
    {
        $::db->update(Record => $self->record_id, {
            created   => $created_date,
            createdby => $createdby,
        });
    }

    my $column_id = $self->layout->column_id;
    my $datum     = $self->field($column_id);
    $datum->current_id($self->current_id);
    $datum->clear_value; # Will rebuild as current_id

    if ($need_app)
    {
        my $id = $::db->create(Record => {
            current_id => $self->current_id,
            created    => DateTime->now,
            record_id  => $self->record_id,
            approval   => 1,
            createdby  => $user_id,
        })->id;
        $self->approval_id($id);
    }

    if ($self->new_entry && $user_id && !$options{draft})
    {
        # New entry, so save record ID to user for retrieval of previous
        # values if needed for another new entry. Use the approval ID id
        # it exists, otherwise the record ID.
        my $id = $self->approval_id || $self->record_id;
        my $this_last = {
            user_id     => $user_id,
            instance_id => $sheet->id,
        };
        my ($last) = $::db->search(UserLastrecord => $this_last)->first;
        if($last)
        {   $last->update({ record_id => $id });
        }
        else
        {   $this_last->{record_id} = $id;
            $::db->create(UserLastrecord => $this_last);
        }
    }

    $self->_need_rec($need_rec);
    $self->_need_app($need_app);
    $self->write_values(%options) unless $options{no_write_values};

    $guard->commit;
}

sub record_in_use($)
{   my ($self, $record_id) = @_;

    my $tables = Linkspace::Column->meta_tables;
    foreach my $table (@$tables)
    {   return 1 if $::db->search($table => { record_id => $record_id })->count;
    }
    0;
}

sub write_values
{   my ($self, %options) = @_;

    # Should never happen if this is called straight after write()
    $self->_has_need_app && $self->_has_need_rec
        or panic "Called out of order - need_app and need_rec not set";

    my $guard = $self->schema->txn_scope_guard;
    my $is_new = $self->new_entry;

    # Write all the values
    my %columns_changed = ($self->current_id => []);
    my (@columns_cached, %update_autocurs);

    my $columns = $self->sheet->layout->columns_search(order_dependencies => 1, exclude_internal => 1);
    foreach my $column (@$columns)
    {
        # Prevent warnings when writing incomplete calc values on draft
        next if $options{draft} && !$column->userinput;

        my $datum = $self->field($column);
        next if $self->linked_id && $column->link_parent; # Don't write all values if this is a linked record

        if ($self->_need_rec || $options{update_only}) # For new records, $need_rec is only set if user has create permissions without approval
        {
            my $v;
            # Need to write all values regardless. This will either be the
            # updated and approved value, if updated before arriving here,
            # or the existing value otherwise
            if ($self->doing_approval)
            {
                # Write value regardless (either new approved or existing)
                $self->_field_write($column, $datum);

                # Leave records where they are unless this user can
                # action the approval
                $self->approver_can_action_column($column)
                    or next;

                # And delete value in approval record
                $::db->delete($column => {
                    record_id => $self->approval_id,
                    layout_id => $column->id,
                });
            }
            elsif(   $column->user_can($is_new ? 'write_new_no_approval' : 'write_existing_no_approval')
                  || !$column->userinput
            )
            {
                # Write new value
                $self->_field_write($column, $datum, %options);

                push @{$columns_changed{$self->current_id}}, $column->id
                    if $datum->changed;
            }
            elsif($is_new)
            {   # Write value. It's a new entry and the user doesn't have
                # write access to this field. This will write a blank
                # value.
                $self->_field_write($column, $datum) if !$column->userinput;
            }
            elsif($column->user_can('write'))
            {   # Approval required, write original value
                panic "update_only set but attempt to hold write for approval"
                    if $options{update_only}; # Shouldn't happen, makes no sense
                $self->_field_write($column, $datum, old => 1);
            }
            else
            {   # Value won't have changed. Write current value (old
                # value will not be set if it hasn't been updated)
                # Write old value
                $self->_field_write($column, $datum, %options);
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

                    # Then see if any fields depend on this autocur (e.g. code fields)
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

        if ($self->_need_app)
        {
            # Only need to write values that need approval
            next unless $datum->is_awaiting_approval;
            $self->_field_write($column, $datum, approval => 1)
                if $is_new ? !$datum->is_blank : $datum->changed;
        }
    }

    # Test all internal columns for changes - these will not have been tested
    # during the write above
    my $internals = $self->sheet->layout->columns_search(only_internal => 1);
    foreach my $column (@$internals)
    {   push @{$columns_changed{$self->current_id}}, $column->id
            if $self->field($column)->changed;
    }

    # If this is an approval, see if there is anything left to approve
    # in this record. If not, delete the stub record.
    if ($self->doing_approval)
    {

        if(! $self->record_in_use($self->approval_id))
        {
            # Nothing left for this approval record. Is there a last_record flag?
            # If so, change that to the main record's flag instead.
            my $lr = $::db->search(UserLastrecord =>
                record_id => $self->approval_id,
            })->first;
            $lr->update({ record_id => $self->record_id }) if $lr;

            # Delete approval stub
            $::db->delete(Record => $self->approval_id);
        }
    }

    # Do we need to update any child records that rely on the
    # values of this parent record?
    if (!$options{draft})
    {
        foreach my $child_id (@{$self->child_record_ids})
        {
            my $child = $self->_sibling_record(user_permission_override => 1);
            $child->find_current_id($child_id);

            my $columns = $self->sheet->layout->columns_search(order_dependencies => 1, exclude_internal => 1);
            foreach my $col (@$columns)
            {   $col->userinput or next; # Calc/rag values will be evaluated during write()

                my $datum_child = $child->field($col);
                my $datum_parent = $self->field($col);
                $datum_child->set_value($datum_parent->set_values, is_parent_value => 1)
                    unless $col->can_child;

            }
            $child->write(%options, update_only => 1);
        }

        # Update any records with an autocur field that are referred to by this
        foreach my $cid (keys %update_autocurs)
        {
            # Check whether this record is one that we're going to write
            # anyway. If so, skip.
            next if grep { $_->current_id == $cid } @{$self->_records_to_write_after};

            my $record = $self->_sibling_record;
            $record->find_current_id($cid);
            $record->field($_)->changed(1) for @{$update_autocurs{$cid}};
            $record->write(%options, update_only => 1, re_evaluate => 1);
        }
    }

    $_->write_values(%options)
        for @{$self->_records_to_write_after};

    $self->_clear_records_to_write_after;

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
                layout      => $self->layout,
                schema      => $self->schema,
                user        => $self->user,
                current_ids => [$cid],
                columns     => $columns_changed{$cid},
                current_new => $self->new_entry,
            );

            if ($ENV{GADS_NO_FORK})
            {
                $alert_send->process;
                return;
            }
            if (my $kid = fork)
            {
                # will fire off a worker and then abandon it, thus making reaping
                # the long running process (the grndkid) init's (pid1) problem
                waitpid($kid, 0); # wait for child to start grandchild and clean up
            }
            else {
                if (my $grandkid = fork) {
                    POSIX::_exit(0); # the child dies here
                }
                else {
                    # We should already be in a try() block, probably with
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
    $self->clear_new_entry; # written to database, no longer new
    $self->_clear_need_rec;
    $self->_clear_need_app;
}

sub set_blank_dependents
{   my $self = shift;

    foreach my $column ($self->layout->columns_search(exclude_internal => 1))
    {
        my $datum = $self->field($column);
        $datum->set_value('')
            if ! $datum->dependent_shown
            && ($datum->column->can_child || !$self->parent_id);
    }
}

# A list of any records to write at the end of writing this one. This is used
# when writing subrecords - the full record may not be able to be written at
# the time of write as it may refer to this one
has _records_to_write_after => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { [] },
);

sub _field_write
{   my ($self, $column, $datum, %options) = @_;

    $column->value_to_write
        or return;

    if ($column->userinput)
    {
        # No datum for new invisible fields
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
            # for each field in the future
            my @rows = $::db->search($table => {
                record_id => $entry->{record_id},
                layout_id => $entry->{layout_id},
            })->all;

            foreach my $row (@rows)
            {
                if (my $entry = pop @entries)
                {   $row->update($entry);
                }
                else
                {   $row->delete; # Now less values than before
                }
            }
        }

        #XXX ???
        # For update_only, there might still be some @entries to be written
        $::db->create($table => $_)
            for @entries;
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

sub user_can_purge
{   my $self = shift;
    $self->current_id ? $self->sheet->user_can("purge") : 0;
}

# Mark this entire record and versions as deleted
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
    $self->user_can_purge
        or error __"You do not have permission to purge records";

    $self->_purge_record_values($self->record_id);
    $::db->delete(Record => $self->record_id);
}

sub restore
{   my $self = shift;
    $self->user_can_purge
        or error __"You do not have permission to restore records";

    $::db->update(Current => $self->current_id, { deleted => undef });
}

sub as_json
{   my $self = shift;
    my $return;
    my $columns = $self->sheet->layout->columns_search(user_can_read => 1);
    foreach my $col (@$columns)
    {   my $short = $col->name_short or next;
        $return->{$short} = $self->field($col)->as_string;
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
            for @{$self->field($col)->html_form};
    }
    join '&', @queries;
}

sub pdf
{   my $self = shift;

    my $now = DateTime->now;
    $now->set_time_zone('Europe/London');

    my $user = $::session->user;
    my $now_formatted = $user->dt2local($now)." at ".$now->hms;

    my $created = $self->created;
    my $updated = $user->dt2local($created)." at ".$created->hms;

    my $pdf = CtrlO::PDF->new(
        footer => "Downloaded by ".$self->user->value." on $now_formatted",
    );

    $pdf->add_page;
    $pdf->heading('Record '.$self->current_id);
    $pdf->heading('Last updated by '.$self->createdby->as_string." on $updated", size => 12);

    my @data    = ['Field', 'Value'];
    my $columns = $self->sheet->layout->columns_search(user_can_read => 1);
    foreach my $col (@$columns)
    {   my $datum = $self->field($col);
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

    my $max_fields = max map +@$_, @data;

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
        # $max_fields does not include field name
        my $gap = $max_fields - $has + 1;
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

# Delete the record entirely from the database, plus its parent current (entire
# row) along with all related records
sub purge_current
{   my $self = shift;

    $self->user_can_purge
        or error __"You do not have permission to purge records";

    my $id = $self->current_id
        or panic __"No current_id specified for purge";

    my $crs = $::db->search(Current => {
        id => $id,
        instance_id => $self->sheet->id,
    })->first
        or error __x"Invalid ID {id}", id => $id;

    $crs->deleted
        or error __"Cannot purge record that is not already deleted";

    my @recs = $::db->search(Current => {
        'curvals.value' => $id,
    },{
        prefetch => { records => 'curvals' },
    })->all;

    if(@recs)
    {   my $recs = join ', ', map {
            my %fields;
            foreach my $record ($_->records) {
                $fields{$_->layout->name} = 1 for $record->curvals;
            }
            my $names = join ', ', keys %fields;
            $_->id." ($names)";
        } @recs;
        error __x"The following records refer to this record as a value (possibly in a historical version): {records}",
            records => $recs;
    }

    my @records = $self->schema->resultset('Record')->search({
        current_id => $id
    })->all;

    # Get creation details for logging at end
    my $createdby = $self->createdby;
    my $created   = $self->created;

    # Start transaction.
    # $@ may be the result of a previous Log::Report::Dispatcher::Try block (as
    # an object) and may evaluate to an empty string. If so, txn_scope_guard
    # warns as such, so undefine to prevent the warning
    undef $@;
    my $guard = $self->schema->txn_scope_guard;

    # Delete child records first
    foreach my $child (@{$self->child_record_ids})
    {
        my $record = $self->_sibling_record;
        $record->find_current_id($child);
        $record->purge_current;
    }

    $self->_purge_record_values($_->id)
        for @records;

    my $which = +{ current_id => $id };
    $::db->update(Record     => $which, { record_id => undef });
    $::db->delete(AlertCache => $which);
    $::db->delete(Record     => $which);
    $::db->delete(AlertSend  => $which);
    $::db->delete(Current    => $id);
    $guard->commit;

    my $user_id = $self->user && $self->user->id;
    info __x"Record ID {id} purged by user ID {user} (originally created by user ID {createdby} at {created}",
        id => $id, user => $user_id, createdby => $createdby->id, created => $created;
}

#XXX I have seen similar lists on other places
my @purge_tables = qw/Ragval Calcval Enum String Intgr Daterange Date Person File Curval/;

sub _purge_record_values
{   my ($self, $rid) = @_;
    my $which = +{ record_id => $rid };

    $::db->delete($_ => $which) for @purge_tables;
    $::db->delete(UserLastrecord => $which);
}

1;

