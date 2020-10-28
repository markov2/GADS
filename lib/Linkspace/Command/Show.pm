## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Command::Show;
use parent 'Linkspace::Command';

use Log::Report 'linkspace';

sub help_line() { "show [OPTIONS]" }

sub help() { <<__HELP }
 ... show
__HELP

sub subcommands
{ ( start => 'dance_start',
  );
}

sub dance_start($)
{   my ($self, $args) = @_;

    ! $args->{files}
        or error __x"No file arguments expected";

    _get_dancer->dance;
}

1;
