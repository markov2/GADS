## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Row;

use warnings;
use strict;

use Log::Report 'linkspace';
use DateTime ();

use Linkspace::Row::Revision     ();
use Linkspace::Row::Revision::Approval ();
use Linkspace::Row::Cell         ();
use Linkspace::Row::Cell::Orphan ();

use Moo;
extends 'Linkspace::DB::Table';

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
of them.  Structural:

   ::Row
      has many ::Row::Revision
         has many ::Row::Cell
             has many ::Datum,
             has ::Column

=head1 METHODS: Constructors

The constructors may pass a 'content' with a 'sheet'-object, only a 'sheet' object,
or neither.  It will break due to recursion when only a 'content' is provided.
=cut

sub path { $_[0]->sheet->path . '/row=' . $_[0]->id }

sub from_record(@)
{   my ($class, $record) = (shift, shift);

    return Linkspace::Row::Draft->from_record($record, @_)
        if __PACKAGE__ eq $class && $record->draftuser_id;

    my $self  = $class->SUPER::from_record($record, @_);

    error __"You do not have access to this deleted row"
        if $self->deleted && !$self->sheet->user_can('purge');

    $self;
}

sub from_revision_id($@)
{   my ($class, $rev_id) = (shift, shift);
    my $rec = $::db->search(Current =>
      { 'record.id' => $rev_id, current_id => 'record.current_id',  },
      { join => 'record' })->single;

    $class->from_record($rec, @_);
}

sub row_by_serial($%)
{   my ($class, $serial, %args) = @_;
    defined $serial ? $class->from_search({sheet => $args{sheet}, serial => $serial}, %args) : undef;
}

sub _row_create($%)
{   my ($class, $insert, %args) = @_;
    my %insert   = %$insert;
    my $revision = delete $insert{revision};

    my $self     = $class->create(\%insert, content => $args{content}, sheet => $args{sheet});
    $self->revision_create($revision, is_initial => 1) if $revision;
    $self;
}

sub _row_update()
{   my ($self, $update, %args) = @_;
    delete $self->{_linked_to} if $update->{linked_row};
    delete $self->{_parent}    if $update->{parent_row};
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

sub _draft_rows($@)
{   my ($class, $sheet, $user) = (shift, shift, shift);
    Linkspace::Row::Draft->search_objects({ sheet => $sheet, draftuser => $user },
       {}, @_, sheet => $sheet,
    );
}

=head1 $row->restore;
Undo row deletion.
=cut

sub restore() { $_[0]->update({ deleted => undef, deleted_by => undef }) }

=head1 $row->purge;
Delete the record entirely from the database, plus its parent current (entire
row) along with all related revisions.
=cut

sub _row_purge
{   my $self = shift;

    my $curvals = $self->sheet->document->curval_cells_pointing_to_row($self);

    if(@$curvals)
    {   my @use = map {
            my %sheets;
            foreach my $record ($_->records) {
                $sheets{$_->sheet->name} = 1 for $record->curvals;
            }
            my $sheet_names = join ', ', sort keys %sheets;
            $_->row_id." ($sheet_names)";
        } @$curvals;
        error __x"These rows refer to this row as a value (possibly in a historical version): {using}",
            using => \@use;
    }

    $_->_row_purge for @{$self->child_rows};

    my $revisions = $self->all_revisions;
    $_->_revision_delete for @$revisions;

    my $which = +{ current_id => $self->id };
    $::db->delete(AlertCache => $which);
    $::db->delete(Record     => $which);
    $::db->delete(AlertSend  => $which);
    $self->delete;

    info __x"Row {row.current_id} purged", row => $self;
}
#-----------------
=head1 METHODS: Accessors
=cut

has content => ( is => 'ro', builder => sub { $_[0]->sheet->content } );
has sheet   => ( is => 'ro', builder => sub { $::session->site->document->sheet($_[0]->sheet_id) } );

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

sub is_deleted   { !! $_[0]->deleted }   # deleted is a date

sub is_draft { 0 }

#-----------------
=head1 METHODS: Manage row revisions
A row has seen one or more revisions.

=head2 my $revision = $row->revision($search, %options);

Collect a specific revision which related to this row.  The C<$search>
may by a (revision record, table 'Record') id, a constant C<'latest'>
(same as calling the C<current()> method), C<'first'> (the original
revision) or a HASH.

The HASH may contain <last_before> with a date ('rewind').
=cut

sub revision($%)
{   my ($self, $search) = (shift, shift);
    push @_, row => $self;

    # Avoid returning duplicates of 'current'
    my $current = $self->current;
    my $found;

    my $class = 'Linkspace::Row::Revision';
    if(ref $search)
    {   if(my $before = $search->{last_before})
        {   my $hist = $self->_revision_latest(created_before => $before);
            return $hist->id==$current->id ? $current : $hist;
        }
        panic(join '#', %$search);
    }
    elsif(is_valid_id $search)
    {   return $search==$current->id ? $current : $class->from_id($search, @_);
    }
    elsif($search eq 'first')
    {   my $first_id = $class->_revisions_first_id($search, @_);
        return $first_id==$current->id ? $current : $class->from_id($first_id, @_);
    }
    elsif($search eq 'latest')
    {   return $current;
    }

    panic $search;
}

=head2 my $revision = $row->revision_create($insert, %options);
=cut

sub revision_create($%)
{   my ($self, $insert) = (shift, shift);
    ! $self->content->rewind
        or error __x"You cannot create revisions on an old table view";

    my $guard = $::db->begin_work;
    my $kill  = $self->sheet->forget_history ? $self->all_revisions : [];
    my $rev   = Linkspace::Row::Revision->_revision_create($self, $insert, @_);

    $self->_set_current($rev);
    $self->revision_delete($_) for @$kill;
    $guard->commit;

    $rev;
}

=head2 \@revisions = $row->all_revisions;
Returns all revisions (before the content rewind), newest first.
=cut

sub all_revisions(%)
{   my $self = shift;
    my $before = $self->content->rewind_formatted;
    my $revs = Linkspace::Row::Revision->_find($self, created_before => $before);
    $self->_set_current($revs->[-1]);
    $revs;
}

=head2 $row->revision_purge($revision);
Remove revision from the database.  The usual C<< $revision->delete >> only
flags the revision as being deleted.
=cut

sub revision_purge($)
{   my ($self, $revision) = @_;

    $self->sheet->user_can('purge')
        or error __"You do not have permission to purge sheet content";

    $revision->_revision_delete;
}

#---------------------
=head1 METHODS: current revision

=head2 my $revision = $row->current;
Get the latest revision of the row: the non-draft with the highest id.
=cut

sub current() { $_[0]->{LR_current} ||= Linkspace::Row::Revision->_revision_latest(row => $_[0]) }
sub _set_current($) { $_[0]->{LR_current} = $_[1] }

=head2 my $cell = $row->created_by;
Returns the Person who created the initial revisions of this row.  This is kept
in the '_created_user' column in every revision.
=cut

sub created_by() { $_[0]->current->cell('_created_user')->datum->person }

=head2 my $count = $row->revision_count;
Returns the number of revisions available for this row.
=cut

sub revision_count
{   my $self = shift;
    $self->_record->search_related('records')->count;
}

#-----------------
=head1 METHODS: Parent/Child relation between rows

When row has a parent, then it will copy some of the cells from the parent,
but can change other fields.

Multi-level parenthood does not exist: a parent cannot be a child itself.
=cut

sub parent_row
{   my $self = shift;
    $self->content->row($self->parent_row_id);
}

sub has_parent_row { !! $_[0]->parent_row_id }

sub child_rows()
{   my $self = shift;
    return [] if $self->parent_row_id;

    $self->search_objects({
        parent_row   => $self,
        deleted      => undef,
        draftuser_id => undef,
    });
}

sub child_row_create()
{   my ($self, %args) = @_;
    $self->content->row_create(%args, parent_row => $self);
}

#---------------------
=head1 METHODS: Approvals

=cut


#---------------------
=head1 METHODS: Curval handling
Curval fields point across sheets.  Let's try to avoid instantiating
all sheets to find these cells.

=head2 \@cells = $doc->curval_cells_pointing_to_me;
=cut

sub curval_cells_pointing_to_me()
{   my $self    = shift;
    my $results = $::db->search(Current =>
        { 'curvals.value' => $self->current_id },
        { prefetch => { records => 'curvals' } }
    );
    my @datums = map $_->curvals, map $_->records, $results->all;
    [ Linkspace::Row::Cell::Orphan->from_record($_), @datums ];
}

1;
