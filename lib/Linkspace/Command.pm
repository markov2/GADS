## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Command;

use Log::Report 'linkspace';

sub help_line() { panic }
sub help() { panic }
sub subcommands() { panic }

1;
