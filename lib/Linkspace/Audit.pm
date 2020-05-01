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

package Linkspace::Audit;

use Log::Report 'linkspace';

use Scalar::Util qw/blessed/;
use DateTime;
use GADS::Datum::Person;
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
