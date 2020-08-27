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

#XXX no idea what 'serial' represents
sub from_serial($%)
{   my ($class, $serial) = (shift, shift);
    defined $serial ? $self->from_search({serial => $serial}) : undef;
}

sub _row_create($%)
{   my ($self, $insert, %args) = @_;
    $insert->{created} = DateTime->now;
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
    $self->update({ deleted => DateTime->now });
}

# Delete the record entirely from the database, plus its parent current (entire
# row) along with all related records
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

sub content { $_[0]->sheet->content }

#XXX MO: No idea yet what being "linking" means.

sub linked_to_row
{   my $self = shift;
    $self->{_linked_to} ||= $self->content->row($self->linked_row_id);
}

has deleted_by => (
    is      => 'lazy',
    builder => sub { $_[0]->site->users->user($_[0]->deleted_by_id) },
);

sub deleted_when { $::db->parse_datetime($_[0])->deleted }

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
{   my ($self, $insert) = @_;
    $insert->{current} = $row;
    Linkspace::Row::Revision->_revision_create($insert, @_, row => $self);
}

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

sub childs()...;

=head1 METHODS: Draft row
=cut

sub is_draft { !! $_[0]->draftuser_id }

1;
