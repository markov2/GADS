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

package Linkspace::Datum::Integer;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

my %ops = (
    '*' => sub { $_[0] * $_[1] },
    '/' => sub { $_[0] / $_[1] },
    '+' => sub { $_[0] + $_[1] },
    '-' => sub { $_[0] - $_[1] },
);

sub _unpack_values($$%)
{   my ($class, $cell, $values, %args) = @_;

    if($cell && @$values==1
       && $values->[0] =~ m!^\h*\(\h*([*+/-])\h*([+-]?[0-9]+)\h*\)\h*$!)
    {   my ($op, $amount) = ($ops{$1}, $2);
        my @old = map $_->value, @{$cell->datums};
        @old or @old = 0;

        return [ map $op->($_, $amount), @old ];
    }

    $values;
}

sub as_integer { int($_[0]->value // 0) }

sub _value_for_code { int $_[2] }

1;
