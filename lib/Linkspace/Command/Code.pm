## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Command::Code;
use parent 'Linkspace::Command';

use Log::Report 'linkspace';

use Getopt::Long qw(GetOptions);
use List::Util   qw(first);

sub help_line() { "code (refresh|) [OPTIONS]" }

sub plugin_help() { <<__HELP }
 ... code refresh

 OPTIONS:
   --site NAME      scan sheets of which site (default from config)
   --sheet NAME     limit scan to one sheet (default all)
   --force       -f recalculate all fields

__HELP

sub subcommands
{ ( refresh => \&code_refresh,
  );
}

sub cmdline_options() { 'site=s', 'sheet=s', 'force|f' }

sub code_refresh($)
{   my ($self, $args) = @_;

    my $site;
    if(my $site_name = $args->{site})
    {   $site = $::linkspace->site_for($site_name)
            or error __x"Unknown site '{name}'", name => $site_name;
        $::session->site($site);
    }
    else
    {   $site = $::session->site;
    }

    my $sheets = $site->document->all_sheets;
    if(my $sheet_name = $args->{sheet})
    {   my $sheet = first { $sheet_name eq $_->name } @$sheets
            or error __x"Cannot find sheet '{name}' in site '{site.name}'",
               name => $sheet_name, site => $site;
        $sheets = [ $sheet ];
    }

    foreach my $sheet (@$sheets)
    {   info "Processing sheet ".$sheet->name;

        foreach my $column (@{$sheet->layout->columns_search})
        {   $column->has_cache or next;

            # Do one column at a time, be afraid for other processes.
            my $lock = $self->lock_ex('code-refresh-'.$sheet->name);

            $self->unlock($lock);
        }
    }
}

1;
