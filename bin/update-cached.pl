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

use Linkspace;
use Tie::Cache;

my $linkspace = Linkspace->new;

tie %{$::db->schema->storage->dbh->{CachedKids}}, 'Tie::Cache', 100;

foreach my $site (@{$linkspace->all_sites})
{
    foreach my $sheet (@{$site->all_sheets})
    {   next if $sheet->no_overnight_update;
        my $layout = $sheet->layout;

        my $cols = $layout->col_ids_for_cache_update;
        next if !@$cols;

        my $page = $sheet->content->search(
            columns              => $cols,
            curcommon_all_fields => 1, # Code might contain curcommon fields not in normal display
            include_children     => 1, # Update all child records regardless
        );

        my %changed;
        while (my $row = $page->row_next)
        {
            foreach my $column ($layout->columns_search(order_dependencies => 1, has_cache => 1))
            {
                my $datum = $row->field($column);
                $datum->re_evaluate(no_errors => 1);
                $datum->write_value;
                push @{$changed{$column->id}}, $row->current_id
                    if $datum->changed;
            }
        }

        # Send any alerts
        foreach my $col_id (keys %changed)
        {   $layout->alert_send(
                current_ids => $changed{$col_id},
                columns     => $col_id,
            )->process;
        }
    }
}
