package Linkspace::Row;

use warnings;
use strict;

use Log::Report 'linkspace';
use DateTime ();

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
             has ::Datum, ::Column

=head1 METHODS: Constructors

The constructors may pass a 'content' with a 'sheet'-object, only a 'sheet' object,
or neither.  It will break due to recursion when only a 'content' is provided.
=cut

sub from_record(@)
{   my $class = shift;
    my $self = $class->SUPER::from_record(@_);

    error __"You do not have access to this deleted record"
        if $self->deleted && !$self->layout->user_can('purge');

    $self;
}

sub from_revision_id($@)
{   my ($class, $rev_id) = (shift, shift);
    $::db->get_object(
      { 'record.id' => $rev_id, current_id => 'record.current_id',  },
      { join => 'record' },
      @_);
}

sub row_by_serial($%)
{   my ($class, $serial) = (shift, shift);
    defined $serial ? $self->from_search({serial => $serial}) : undef;
}

sub _row_create($%)
{   my ($class, $insert, %args) = @_;

    my $guard  = $::db->begin_work;
    my $revision;
    if(my $data = delete $insert->{revision}) 
    {   # May cast validation errors
        $revision = $class->_revision_prepare($data);
    }

    my $row = $self->insert($insert, content => $args{content});
    Linkspace::Row::Revision->_revision_create($revision, $row, @_);

    $guard->commit;
    $row;
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

    $_->purge for @{$self->child_rows};

    my $revisions = $self->revisions;
    $_->_revision_delete for @$revisions;

    my $which = +{ current_id => $id };
    $::db->delete(AlertCache => $which);
    $::db->delete(Record     => $which);
    $::db->delete(AlertSend  => $which);
    $self->delete;

    info __x"Row {row.current_id} purged", row => $self;
}
#-----------------
=head1 METHODS: Accessors
=cut

has content => (
    is      => 'ro',
    builder => sub { $_[0]->sheet->content },
);

has sheet => (
    is      => 'ro',
    builder => sub { $::session->site->document->sheet($_[0]->sheet_id) },
);

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

sub nr_rows()
{   # query to count rows which are not deleted
}

sub first_row()
{   # Used in test-scripts: current_id does not need to start at 1
}

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
    {   if(my $before = $search{last_before})
        {   my $hist = $class->_revision_latest(created_before => $before);
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
{   my ($self, $revision) = (shift, shift);
    my $guard  = $::db->begin_work;
    my $insert = $self->revision_prepare($revision);
    my $rev    = Linkspace::Row::Revision->_revision_create($insert, $self, @_);
    $guard->commit;
    $rev;
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
     builder => sub { Linkspace::Row::Revision->_revision_latest(row => $self) },
);

=head2 $row->set_current($revision);
Make the C<$revision> the new latest version.
=cut

#XXX more work expected
sub set_current($) { $_[0]->current($_[0]) }

=head2 my $cell = $row->created_by;
Returns the Person who created the initial revisions of this row.  This is kept
in the '_created_user' column in every revision.
=cut

sub created_by() { $_[0]->current->cell('_created_user')->datum }

#-----------------
=head1 METHODS: Parent/Child relation between rows
XXX No idea what this exactly means.
=cut

sub parent_row
{   my $self = shift;
    $self->content->row($self->parent_row_id);
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

sub child_row_create()
{   my ($self, %args) = @_;
    $self->content->row_create(%args, parent_row => $self);
}

#---------------------
=head1 METHODS: Draft row
=cut

sub is_draft { !! $_[0]->draftuser_id }

#XXX must start a new row
sub draft_create() {...}

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
        { 'curvals.value' => $row->current_id },
        { prefetch => { records => 'curvals' } }
    );
    my @datums = map $_->curvals, map $_->records, $results->all;
    [ Linkspace::Row::Cell::Orphan->from_record($_), @datums ];
}

1;
