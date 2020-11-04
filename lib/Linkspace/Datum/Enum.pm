## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Datum::Enum;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

sub _unpack_values($$$%)
{   my ($class, $column, $old_datums, $values, %args) = @_;
    $column->to_ids($values);
}

sub value_hash($)
{   my ($self, $column) = @_;
    my $ev = $column->enumval($self->value);
    +{ id => $ev->id, text => $ev->name, deleted => $ev->deleted };
}

sub _value_for_code
{   my ($self, $cell, $enum_id) = @_;
     +{ id => $enum_id, value => $cell->column->enumval_name($enum_id) };
}

1;
