## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::Config;

use Path::Class qw(dir);
use Moo;

with 'MooX::Singleton';

has config => (
    is       => 'rw',
    required => 1,
    trigger  => sub {
        my $self = shift;
        $self->clear_gads;
        $self->clear_login_instance;
        $self->clear_dateformat;
        $self->clear_dateformat_datepicker;
    },
);

has app_location => (
    is => 'ro',
);

has template_location => (
    is => 'lazy',
);

sub _build_template_location
{   my $self = shift;
    dir($self->app_location, "views");
}

has gads => (
    is      => 'ro',
    lazy    => 1,
    clearer => 1,
    builder => sub { ref $_[0]->config eq 'HASH' && $_[0]->config->{gads} },
);

has login_instance => (
    is      => 'ro',
    lazy    => 1,
    clearer => 1,
    builder => sub { $_[0]->gads->{login_instance} || 1 },
);

has dateformat => (
    is      => 'ro',
    lazy    => 1,
    clearer => 1,
    builder => sub {
        my $self = shift;
        ref $self->gads eq 'HASH' && $self->gads->{dateformat} || 'yyyy-MM-dd';
    },
);

has dateformat_datepicker => (
    is      => 'ro',
    lazy    => 1,
    clearer => 1,
    builder => sub {
        my $self = shift;
        my $dateformat = $self->dateformat;
        # Convert CLDR to datepicker.
        # Datepicker accepts:
        # d, dd: Numeric date, no leading zero and leading zero, respectively. Eg, 5, 05.
        # - No change required
        # D, DD: Abbreviated and full weekday names, respectively. Eg, Mon, Monday.
        $dateformat =~ s/eeee/DD/;
        $dateformat =~ s/eee/D/;
        # m, mm: Numeric month, no leading zero and leading zero, respectively. Eg, 7, 07.
        $dateformat =~ s/MM(?!M)/mm/;
        $dateformat =~ s/M(?!M)/m/;
        # M, MM: Abbreviated and full month names, respectively. Eg, Jan, January
        $dateformat =~ s/MMMM/MM/;
        $dateformat =~ s/MMM/M/;
        # yy, yyyy: 2- and 4-digit years, respectively. Eg, 12, 2012.
        # - No change required

        return $dateformat;
    },
);

1;
