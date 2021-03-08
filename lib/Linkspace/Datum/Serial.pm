## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Serial;
use warnings;
use strict;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

sub value      { $_[0]->record->serial }
sub as_integer { $_[0]->value }

1;

