## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Datum::Person;
use Log::Report 'linkspace';

use Scalar::Util     qw(blessed);
use Linkspace::Util  qw(is_valid_id);

### 2020-11-04: columns in GADS::Schema::Result::Person
# id           value        child_unique layout_id    record_id

use Moo;
extends 'Linkspace::Datum';

sub db_table { 'Person' }

around BUILDARGS => sub {
    my ($orig, $class) = (shift, shift);
    my $args = @_==1 ? shift : { @_ };
    my $v = $args->{value} or panic;

    if(blessed $v && $v->isa('Linkspace::User'))
    {   $args->{value}  = $v->id;
        $args->{person} = $v;
    }
    $class->$orig($args);
};

sub _unpack_values($$$%)
{   my ($class, $column, $old_datums, $values, %args) = @_;
    my $users = $::session->site->users;

    my @people;
    foreach my $value (@$values)
    {   my $person;
        if(blessed $value && $value->isa('Linkspace::User'))
        {   $person = $value;
        }
        elsif(my $user_id = is_valid_id $value)
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

sub compare_values { panic }
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
        organisation => do { my $o = $person->organisation; $o ? $o->name : undef },
        department   => do { my $d = $person->department; $d ? $d->name : undef },
        team         => do { my $t = $person->team; $t ? $t->name : undef },
        title        => do { my $t = $person->title; $t ? $t->name : undef },
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

