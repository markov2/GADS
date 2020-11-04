## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Row::Cell::Linked;
use parent 'Linkspace::Row::Cell';

use Linkspace::Row::Cell::Orphan;

sub is_linked { 1 }

sub link_parent()
{   my $self = shift;

    $self->{link_parent} ||= Linkspace::Row::Cell::Orphan->new(
        row_id    => $self->value,
        column_id => $self->column->link_parent_id,
    );
}

sub as_string()  { $_[0]->link_parent->as_string }

sub as_integer() { $_[0]->link_parent->as_integer }

1;
