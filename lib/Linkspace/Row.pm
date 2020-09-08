package Linkspace::Row;

use warnings;
use strict;

use Moo;
extends 'Linkspace::DB::Table';

use Log::Report 'linkspace';
use DateTime ();

sub db_table { 'Current' }

sub db_field_rename { +{
    linked_id => 'linked_row_id',
    parent_id => 'parent_row_id',
    deletedby => 'deleted_by_id',  # Person
} };

__PACKAGE__->db_accessors;

### 2020-08-26: columns in GADS::Schema::Result::Current
# id           deleted      draftuser_id parent_id
# instance_id  deletedby    linked_id    serial

=head1 NAME
Linkspace::Row - Manage one row contained in one sheet

=head1 SYNOPSIS
   $row = $content->row($current_id);
   $row = $content->row_by_serial($serial);

=head1 DESCRIPTION
The Row has at least one revision, which are L<Linkspace::Row::Revision> objects.

The ::Row and ::Row::Revision objects are not cached, because there are too many
of them.

=head1 METHODS: Constructors

=cut

sub from_record(@)
{   my $class = shift;
    my $self = $class->SUPER::from_record(@_);

    error __"You do not have access to this deleted record"
        if $self->deleted && !$self->layout->user_can('purge');

    $self;
}

sub row_by_serial($%)
{   my ($class, $serial) = (shift, shift);
    defined $serial ? $self->from_search({serial => $serial}) : undef;
}

sub _row_create($%)
{   my ($self, $insert, %args) = @_;
    $self->insert($insert, content => $args{content});
}

sub _row_update()
{   my ($self, $update, %args) = @_;
    delete $self->{_linked_to} if $update->{linked_row_id} || $update->{linked_row};
    delete $self->{_parent}    if $update->{parent_row_id} || $update->{parent_row};
    $self->update($update);
    $self;
}

sub _row_delete()
{   my ($self) = @_;
    $self->update({
        deleted    => DateTime->now,
        deleted_by => $::session->user,
    });
}

=head1 $row->restore;
Undo row deletion.
=cut

sub restore() { $_[0]->update({ deleted => undef, deleted_by => undef }) }

=head1 $row->purge;
Delete the record entirely from the database, plus its parent current (entire
row) along with all related revisions.
=cut

sub purge
{   my $self = shift;

    $self->sheet->user_can('purge')
        or error __"You do not have permission to purge records";

    my @recs = $::db->search(Current => {
        'curvals.value' => $self->id,
    },{
        prefetch => { records => 'curvals' },
    })->all;

    if(@recs)
    {   my @use = map {
            my %cells;
            foreach my $record ($_->records) {
                $cells{$_->sheet->name} = 1 for $record->curvals;
            }
            my $names = join ', ', keys %cells;
            $_->id." ($names)";
        } @recs;
        error __x"The following records refer to this record as a value (possibly in a historical version): {records}",
            records => \@use;
    }

    $_->purge for @{$self->child_rows};

    my $revisions = $self->revisions;
    $_->_revision_delete for @$revisions;

    my $which = +{ current_id => $id };
    $::db->delete(AlertCache => $which);
    $::db->delete(Record     => $which);
    $::db->delete(AlertSend  => $which);

    $self->delete;

    info __x"Row {id} purged by user {user} (was created by user {createdby} at {created}",
        id => $self->current_id, user => $::session->user->fullname,
        createdby => $self->created_by->fullname, created => $self->created_when;
}

#-----------------
=head1 METHODS: Accessors
=cut

has content => (
    is       => 'ro'
    required => 1,
);

sub sheet { $_[0]->content->sheet }

#XXX MO: No idea yet what being "linked" means.

sub linked_to_row
{   my $self = shift;
    $self->{_linked_to} ||= $self->content->row($self->linked_row_id);
}

sub deleted_by
{   my $self = shift;
    my $user_id = $self->deleted_by_id or return;
    $self->site->users->user($user_id);
}

sub deleted_when
{   my $date = shift->deleted or return;
    $::db->parse_datetime($date);
}

sub is_deleted   { !! $self->deleted }   # deleted is a date

# Whether this row has been collected as historical record.
has is_history => ( is => 'ro' );

#-----------------
=head1 METHODS: Manage row revisions
A row has seen one or more revisions.

=head2 my $revision = $row->revision($rev_id, %options);
Collect a specific revision which related to this row.
=cut

sub revision($%)
{   my ($self, $rev_id) = (shift, shift);
    Linkspace::Row::Revision->from_id($rev_id, @_, row => $self);
}

=head2 my $revision = $row->revision_create($insert, %options);
=cut

sub revision_create($%)
{   my ($self, $insert) = (shift, shift);
    Linkspace::Row::Revision->_revision_create($insert, $self, @_);
}

=head2 my $revision = $row->revision_update($revision, $update, %options);
=cut

sub revision_update($$%)
{   my ($self, $rev, $update) = (shift, shift, shift);
    $rev->_revision_update($update, @_);
}

=head2 my $revision = $row->current;
Get the latest revision of the row: the non-draft with the highest id.
=cut

has current = (
     is      => 'rw',
     lazy    => 1,
     builder => sub
     {   my $self = shift;
         Linkspace::Row::Revision->_revision_latest($self,
             created_before => $self->content->rewind,
         );
     },
);

=head2 $row->set_current($revision);
Make the C<$revision> the new latest version.
=cut

#XXX more work expected
sub set_current($) { $_[0]->current($_[0]) }

#-----------------
=head1 METHODS: Parent/Child relation
XXX No idea what this exactly means.
=cut

has _parent    => (is => 'rw');
sub parent_row
{   my $self = shift;
    $self->{_parent} ||= $self->content->row($self->parent_row_id);
}

sub has_parent_row { !! $_[0]->parent_row_id }

sub child_rows()
{   my $self = shift;
    return [] if $self->parent_row_id;  # no multilevel parental relations

    $self->search_objects({
        parent_row   => $self,
        deleted      => undef,
        draftuser_id => undef,
    });
}


#---------------------
=head1 METHODS: Draft row
=cut

sub is_draft { !! $_[0]->draftuser_id }

#XXX must start a new row
sub draft_create() {...}

#---------------------
=head1 METHODS: Approvals

=head2 
=cut



1;

1;
