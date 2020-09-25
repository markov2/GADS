=pod
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

package Linkspace::Row::Cell::Orphan;
use parent 'Linkspace::Row::Cell';

=head1 DESCRIPTION

Curval cells can spring into existence without any build-up for parential
structural elements: no row-revision, no row, no sheet... nothing.  But
they must be made available.  This can also be used for other kinds of cells.

This implementation caches a lot more than its base class, in an
attempt to simplify the execution path.

=cut

sub from_record($%)
{   my ($class, $record, %args) = @_;
    $class->new(datum_record => $record);
}

sub sheet() { $_[0]->{sheet} ||= $_[0]->row->sheet }

sub row
{   my $self = shift;
    $self->{row} ||= Linkspace::Row->from_revision_id($self->{datum_record}{record_id});
}

sub revision
{   my $self = shift;
    $self->{revision} = $self->row->revision($self->{datum_record}{record_id});
}

sub column
{   my $self = shift;    # does not need sheet
    $self->{column} ||= $::session->site->document->column($self->{datum_record}{layout_id});
}

1;
