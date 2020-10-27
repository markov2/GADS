## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::ID;

use warnings;
use strict;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

has value => (
    is      => 'lazy',
    builder => sub { $_[0]->current_id },
);

sub as_string  { $_[0]->value }
sub as_integer { $_[0]->value || undef }

sub _value_for_code($$$) { $_[2] }

1;

