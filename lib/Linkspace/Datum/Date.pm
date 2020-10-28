## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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
