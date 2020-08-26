use warnings;
use strict;

package Linkspace::Command::Dance;
use parent 'Linkspace::Command';

use Log::Report 'linkspace';

sub _get_dancer()
{   eval "require GADS";
    panic $@ if $@;
    'GADS';
}

sub help_line() { "dancer start|stop [OPTIONS]" }

sub help() { <<__HELP }
 ... dance start
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
