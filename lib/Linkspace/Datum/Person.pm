## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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

