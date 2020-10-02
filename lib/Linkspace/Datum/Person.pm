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

package Linkspace::Datum::Person;
use Log::Report 'linkspace';

use warnings;
use strict;

use DateTime;
use HTML::Entities;

use Moo;
extends 'Linkspace::Datum';
with 'GADS::Role::Presentation::Datum::Person';

after set_value => sub {
    my ($self, $value, %options) = @_;
    ($value) = flat $value;
    my $new_id;
    my $clone = $self->clone;

    {   # User input.
        # First check if a textual value has been provided (e.g. import)
        if($value && $value !~ /^[0-9]+$/)
        {   # Swap surname/forename if no comma
            my $orig = $value;
            $value =~ s/(.*)\h+(.*)/$2, $1/ if $value !~ /,/;
            # Try and find in users
            (my $p) = grep {$value eq $_->value} @{$self->column->people};
            error __x"Invalid name '{name}'", name => $orig if !$p;
            $value = $p->id if $p;
        }
        !$value || $options{no_validation} || (grep $value == $_->id, @{$self->column->people}) || $value == $self->id # Unchanged deleted user
            or error __x"'{int}' is not a valid person ID"
                , int => $value;
        $value ||= undef; # Can be empty string, generating warnings
        $new_id = $value;
        # Look up text value
    }
    if (
           (!defined($self->id) && defined $new_id)
        || (!defined($new_id) && defined $self->id)
        || (defined $self->id && defined $new_id && $self->id != $new_id)
    ) {
        $self->changed(1);
        $self->id($new_id);
    }

    $self->oldvalue($clone);
};

sub search_values_unique { [ shift->text ] }

sub text { shift->user->value }

sub user_id    { $_[0]->value }
sub person     { $::session->site->users->user($_[0]->user_id) }

sub ids        { [ $_[0]->id ] }
sub value      { $_[0]->id }
sub as_string  { $_[0]->text // "" }
sub as_integer { $_[0]->id // 0 }

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
        text         => $person->text,
    };
}

1;

