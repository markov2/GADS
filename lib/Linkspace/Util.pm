=pod
GADS - Globally Accessible Data Store
Copyright (C) 2017 Ctrl O Ltd

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

package Linkspace::Util;
use parent 'Exporter';

our @EXPORT_OK = qw/
    config_util
    email_valid
    to_cldr_datetime
/;

use DateTime::Format::CLDR    ();
use DateTime::Format::ISO8601 ();
use Scalar::Util  qw(blessed);

my ($cldr_date, $cldr_datetime);

sub config_util($)
{   my $config = shift;
    my $format = $config->dateformat;

    $cldr_date = DateTime::Format::CLDR->new(pattern => $format);
    $cldr_datetime = DateTime::Format::CLDR->new(pattern => "$format HH:mm:ss");
}

# Noddy email address validator. Not much point trying to be too clever here.
# We don't use Email::Valid, as that will check for RFC822 address as opposed
# to pure email address on its own.
sub email_valid($)
{   $_[0] =~ m/^[=+\'a-z0-9._-]+@[a-z0-9.-]+\.[a-z]{2,10}$/i;
}

# Convert a date value into a DateTime object
sub to_cldr_datetime($)
{   my $value = shift or return;
    return $value if blessed $value && $value->isa('DateTime');

    # If there's a space in the input value, assume it includes a time as well
    my $cldr = $value =~ / / ? $cldr_datetime : $cldr_date;
    $cldr->parse_datetime($value);
}

sub to_iso_datetime($)
{   my $stamp = shift or return;
    DateTime::Format::ISO8601->parse_datetime($stamp);
}

1;

