## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Row::Cell::Orphan;
use parent 'Linkspace::Row::Cell';

use Linkspace::Util   qw(to_id);

=head1 DESCRIPTION

Curval and Linked cells can spring into existence without any
build-up for parential structural elements: no row-revision, no row,
no sheet... nothing.  But they must be made available.  This can also
be used for other kinds of cells.

This implementation caches a lot more than its base class, in an
attempt to simplify the execution path.

=cut

sub from_results($%)
{   my ($class, $results, %args) = @_;

    # For instance, search may hit a datum record.  But we need to revive
    # the whole cell, probably more than one datum in it.  We're not keeping
    # the single datum result (for now).

    $class->new(
        revision_id => to_id $args{revision} || $results->{record_id},
        column_id   => to_id $args{column}   || $results->{layout_id},
        %args,
    );
}

sub sheet() { $_[0]->{sheet} ||= $_[0]->row->sheet }

sub row
{   my $self = shift;
    $self->{row}      ||= $self->{row_id}
      ? Linkspace::Row->from_id($self->{row_id})
      : Linkspace::Row->from_revision_id($self->{revision_id});
}

sub revision
{   my $self = shift;
    $self->{revision} ||= $self->row->revision($self->{revision_id});
}

sub column
{   my $self = shift;    # does not need sheet
    $self->{column} ||= $::session->site->document->column($self->{column_id});
}

1;
