#!/usr/bin/perl

=pod
GADS - Globally Accessible Data Store
Copyright (C) 2014 Ctrl O Ltd

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=cut

use FindBin;
use lib "$FindBin::Bin/../lib";

use Linkspace;

my $linkspace = Linkspace->start;
my $user = $::session->user;

foreach my $site (@{$linkspace->all_sites})
{   $::session = Linkspace::Session->new(site => $site, user => $user);

    foreach my $sheet (@{$site->document->all_sheets})
    {
        foreach my $view (@{$sheet->views->all_views})
        {
            $view->has_alerts
              ? $view->alert_update_cache(all_users => 1)
              : $view->clean_cached;
        }
    }
}
