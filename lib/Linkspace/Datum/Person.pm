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

package Linkspace::Datum::Person;
use Log::Report 'linkspace';

use DateTime;
use HTML::Entities;

use Linkspace::Util  qw(is_valid_id);

use Moo;
extends 'Linkspace::Datum';

sub _unpack_values($$%)
{   my ($class, $cell, $values, %args) = @_;
    my $users = $::db->session->site->users;

    my @people;
    foreach my $value (@$values)
    {   my $person;
        if(my $user_id = is_valid_id $value)
        {   $person = $users->user($user_id);
        }
        else
        {   $person = $users->user_by_fullname($value);
        }

        $person
            or error __x"Invalid name '{name}'", name => $value;

        push @people, $person;
    }
    \@people;
}

sub search_values_unique { [ shift->text ] }

sub person_id  { $_[0]->value }

has person => (
    is      => 'lazy',
    builder => sub { $::session->site->users->user($_[0]->value) },
);

sub _value_for_code
{   my $person = shift->person;
    +{
        surname      => $person->surname,
        firstname    => $person->firstname,
        email        => $person->email,
        freetext1    => $person->freetext1,
        freetext2    => $person->freetext2,
        organisation => $person->organisation,
        department   => $person->department,
        team         => $person->team,
        title        => $person->title,
        text         => $person->fullname,
    };
}

#XXX Multivalue not supported: fields and details overwritten
sub presentation($$)
{   my ($self, $cell, $show) = @_;

    delete $show->{value};
    my $person = $self->person;

    my @details;
    if(my $email = $person->email)
    {   push @details, { value => $email, type => 'email' };
    }

    if(my $def1 = $person->freetext1)
    {   push @details, +{
            definition => $def1,
            value => $::session->site->register_freetext1_name,
            type  => 'text',
        };
    }

    if(my $def2 = $person->freetext2)
    {   push @details, +{
            definition => $def2,
            value => $::session->site->register_freetext2_name,
            type => 'text',
        };
    }

    $show->{details} = \@details;
    $show->{text}    = $person->fullname;
}

1;

