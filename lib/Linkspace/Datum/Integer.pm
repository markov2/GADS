## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Datum::Integer;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

sub db_table { 'Intgr' }

my %ops = (
    '*' => sub { $_[0] * $_[1] },
    '/' => sub { $_[0] / $_[1] },
    '+' => sub { $_[0] + $_[1] },
    '-' => sub { $_[0] - $_[1] },
);

sub _unpack_values($$$%)
{   my ($class, $column, $old_datums, $values, %args) = @_;

    if(@$values==1 && $values->[0] =~ m!^\h*\(\h*([*+/-])\h*([+-]?[0-9]+)\h*\)\h*$!)
    {   my ($op, $amount) = ($ops{$1}, $2);
        my @old = map $_->value, @$old_datums;
        @old or @old = 0;

        return [ map $op->($_, $amount), @old ];
    }

    $values;
}

sub as_integer { int($_[0]->value // 0) }

sub _value_for_code { int $_[2] }

sub sortable() { sprintf "%020d", $_[0]->value }  # string comparison, so pad with enough zeros

1;
