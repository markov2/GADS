## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Audit;

use Log::Report 'linkspace';
use Scalar::Util qw/blessed/;
use DateTime;

use Moo;
use MooX::Types::MooseLike::Base qw/ArrayRef HashRef/;

has filtering => (
    is      => 'rw',
    isa     => HashRef,
    coerce  => sub {
        my $value  = shift;

        my $user       = $::session->user;
        $value->{from} = $user->local2dr($value->{from}) || DateTime->now->subtract(days => 7);
        $value->{to}   = $user->local2dr($value->{to})   || DateTime->now;
        $value;
    },
    builder => sub { +{} },
);

sub audit_types
{   [ qw/user_action login_change login_success logout login_failure/ ];
}

sub logs
{   my $self = shift;

    my $filtering = $self->filtering;

    my %search = (
        datetime => {
            -between => [
                $::db->format_datetime($filtering->{from}),
                $::db->format_datetime($filtering->{to}),
            ],
        },
    );

    $search{method} = uc $filtering->{method} if $filtering->{method};
    $search{type}   = $filtering->{type}      if $filtering->{type};

    if(my $user = $filtering->{user})
    {   $search{user_id} = blessed $user ? $user->id : $user;
    }

    my @logs = $::db->search(Audit => \%search, {
        prefetch => 'user',
        order_by => { -desc => 'datetime' },
        result_class => 'HASH',
    })->all;

    my %people;
    $_->{user} = $people{$_} ||=
        GADS::Datum::Person->new(init_value => { value => $_->{user} })
        for @logs;

    \@logs;
}

sub csv
{   my $self = shift;
    my $csv  = Text::CSV::Encoded->new({ encoding  => undef });

    # Column names
    $csv->combine(qw/ID Username Type Time Description/)
        or error __x"An error occurred producing the CSV headings: {err}", err => $csv->error_input;
    my $csvout = $csv->string."\n";

    # All the data values
    foreach my $row (@{$self->logs})
    {
        $csv->combine($row->{id}, $row->{user}->username, $row->{type}, $row->{datetime}, $row->{description})
            or error __x"An error occurred producing a line of CSV: {err}",
                err => "".$csv->error_diag;
        $csvout .= $csv->string."\n";
    }
    $csvout;
}

sub log
{   my ($class, $log) = @_;
    $::db->create(Audit => $log);
}

1;
