## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Command;

use Log::Report 'linkspace';

use Fcntl qw(:flock SEEK_END);

sub help_line() { panic }
sub plugin_help() { panic }
sub subcommands() { panic }
sub cmdline_options() { () }

# my $lock = $self->lock_ex('unique-name');
# $self->unlock($lock);

sub lock_ex($)
{   my $name    = shift;
    my $lockdir = $::linkspace->settings_for('lock_dir');

    -d $lockdir || mkdir $lockdir
        or error __x"Cannot create directory for locks in '{dir}'", dir => $lockdir;

     my $fn = "$lockdir/$name";
     unless(-f $fn)
     {   open my $cr, '>:raw', $fn
            or error __x"Cannot create lock file '{filename}'", filename => $fn;
         $cr->close;
     }

     open my $fh, '<:raw', $fn or panic;
     flock $fh, LOCK_EX or fault __x"Cannot lock '{filename}'", filename => $fn;
     $fh;
}

sub unlock($)
{   my ($self, $fh) = @_;
    flock $fh, LOCK_UN or fault __x"Cannot unlock";
}

1;
