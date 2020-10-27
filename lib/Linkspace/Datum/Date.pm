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

use warnings;
use strict;

package Linkspace::Datum::Date;

use Log::Report 'linkspace';
use DateTime ();

use Linkspace::Util qw/parse_duration flat/;

use Moo;
extends 'Linkspace::Datum';

#XXX for data which has an external origin needs: $column->parse_date($_)

sub _unpack_values($$%)
{   my ($class, $cell, $values, %args) = @_;

    if($args{bulk} && @$values==1)
    {   if(my $step = parse_duration $values->[0])
        {   my @dates = map $_->value->clone, @{$cell->datums};
            push @dates, DateTime->now unless @dates;
            return [ map $_->add_duration($step), @dates ];
        }
    }

    my $to_dt;
    if(($args{source} // 'db') eq 'user')
    {   my $site = $::session->site;
        $to_dt = sub { blessed $_[0] && $_[0]->isa('DateTime') ? $_[0]
          : $site->local2dt(auto => $_[0])
          };
    }
    else
    {   $to_dt = sub { blessed $_[0] && $_[0]->isa('DateTime') ? $_[0]
          : $_[0] =~ / / ? $::db->parse_datetime($_[0])
          :                $::db->parse_date($_[0])
          };
    }

    my @dates;
    foreach my $value (@$values)
    {   my $dt = $to_dt->($value);

        # If the timezone is floating, then assume it is UTC (e.g. from MySQL
        # database which do not have timezones stored). Set it as UTC, as
        # otherwise any changes to another timezone will not make any effect
        $dt->set_time_zone('UTC') if $dt->time_zone->is_floating;

        $dt->set_time_zone($::session->site->timezone);
    }

    \@dates;
}

sub _value_for_code { $_[0]->_dt_for_code($_[2]) }

1;
