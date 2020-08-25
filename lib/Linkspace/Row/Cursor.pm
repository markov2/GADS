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

package Linkspace::Row::Cursor;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::DB::Table';

sub db_table { 'UserLastrecord' }

__PACKAGE__->db_accessors;

### 2020-08-25: columns in GADS::Schema::Result::UserLastrecord
# id          instance_id user_id     record_id

=head1 NAME

Linkspace::Row::Cursor - points in the sheet to where the user is

=head1 SYNOPSIS

  my $cursor = $user->row_cursor($sheet);
  my $row    = $sheet->content->row_revision($cursor->revision);
  my $row    = $cursor->row_revision;   # same

=head1 DESCRIPTION

For each sheet which a user has used, record is kept to remember where the
user was active.  This cursor points to a revision of a row.

=head1 METHODS: Constructors
=cut

sub _cursor_create($%)
{   my ($class, $insert, %options) = @_;
    $class->create($insert, sheet => $insert->{sheet});
}

sub _cursor_update($%)
{   my ($self, $update, %options) = @_;
    $self->update($update);
}

sub _cursor_delete()
{   my $self = shift;
    $self->delete;
}

=head2 my $cursor = $class->for_user($user, $sheet);
=cut

sub for_user($$)
{   my ($class, $user, $sheet) = (shift, shift, shift);
    $class->from_search({user => $user, sheet => $sheet}, sheet => $sheet, @_);
}

=head2 $cursor->move($revision);
Move the user's cursor to the specified row C<$revision>.  When there is no cursor
yet, it gets created.
=cut

sub move($)
{   my ($self, $rev) = @_;
    $self->update({ sheet => $self->sheet, user_id => $self->user_id, revision => $rev });
    $self;
}

=head2 my $revision = $cursor->row_revision(%options);
Collect the revision of the row where the cursor points to.  That might not be the
latest revision.  It may even have disappeared.

The C<%options> are passed to the construction of the C<Linkspace::Row::Revision>
object which is returned.
=cut

sub row_revision()
{   my $self = shift;
    $self->sheet->content->row_revision($self->revision, @_)
}

1;
