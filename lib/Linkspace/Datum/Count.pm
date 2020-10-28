## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Count;

use warnings;
use strict;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

sub as_string  { my $i = $_[0]->as_integer; defined $i ? "$i unique" : undef }
sub as_integer { my $v = $_[0]->value; defined $v ? int($v || 0) : undef }

1;
