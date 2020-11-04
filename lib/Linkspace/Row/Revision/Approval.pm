## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Row::Revision::Approval;

use Linkspace::Util   qw(to_id);

use Moo;
extends 'Linkspace::Row::Revision';

=head1 NAME
Linkspace::Row::Revision::Approval - Rows which require approval

=head1 DESCRIPTION
Someone may not have the right to update (all) of the row fields
him/herself, but may need confirmation on the value of certain columns.
In that case, an approval revision is created.  Some other person has
the permission to confirm these values.

This revision type is used when either preparation for approval or doing
approval.  "Normal" logic will ignore the existence of these records.

=head1 METHODS: Constructors
=cut

# Bootstrapped in SUPER based on needs_approval flag

#--------------------------
=head1 METHODS: Accessors

=head2 my $base = $revision->approval_base;
Returns the revision where the to-be-approved has been based on. The returned
might be an approval revision itself.
=cut

has approval_base => (
    is      => 'lazy',
    builder => sub { $_[0]->row->revision($_[0]->approval_base_id) },
);

=head2 \@cells = $revision->all_cells;
Returns all cells for the base row, overruled by the cells which are to be
approved.
=cut

sub all_cells()
{   my $self = shift;
    my $list = map +($_->name => $_),
       @{$self->appoval_base->all_cells}, @{$self->SUPER::all_cells};
    values %$list;
}

=head2 my $cell = $revision->cell($column);
Returns the cell to be approved, or (when the cell is not waiting for approval)
from the base record (recursively).
=cut

sub cell($)
{   my ($self, $column) = @_;
    $self->_cells->{to_id $column} || $self->approval_base->cell($column);
}

sub _cell_create($$%)
{   my ($self, $column, $datums, %args) = @_;

      $args{need_approval}
    ? $self->SUPER::_cell_create($column, $datums, %args)
    : $self->approval_base->_cell_create($column, $datums, %args);
}

=head2 $revision->approve;
Approve all cells which are part of this row.
=cut

sub approve()
{   my $self = shift;
    ...;
}

1;
