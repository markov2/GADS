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

use warnings;
use strict;

package Linkspace::Datum::Enum;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

sub _unpack_values($$%)
{   my ($class, $cell, $values, %args) = @_;
    $cell->column->to_ids($values);
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
