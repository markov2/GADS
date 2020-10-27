## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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
