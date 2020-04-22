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

package GADS::Datum::Person;

use DateTime;
use HTML::Entities;
use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use namespace::clean;

extends 'GADS::Datum';

with 'GADS::Role::Presentation::Datum::Person';

after set_value => sub {
    my ($self, $value, %options) = @_;
    ($value) = @$value if ref $value eq 'ARRAY';
    my $new_id;
    my $clone = $self->clone;
    if (ref $value)
    {
        # Used in tests to create user at same time.
        if ($value->{email})
        {
            $new_id = $self->schema->resultset('User')->find_or_create($value)->id;
            $self->column->clear_people;
        }
    }
    else {
        # User input.
        # First check if a textual value has been provided (e.g. import)
        if ($value && $value !~ /^[0-9]+$/)
        {
            # Swap surname/forename if no comma
            my $orig = $value;
            $value =~ s/(.*)\h+(.*)/$2, $1/ if $value !~ /,/;
            # Try and find in users
            (my $p) = grep {$value eq $_->value} @{$self->column->people};
            error __x"Invalid name '{name}'", name => $orig if !$p;
            $value = $p->id if $p;
        }
        !$value || $options{no_validation} || (grep {$value == $_->id} @{$self->column->people}) || $value == $self->id # Unchanged deleted user
            or error __x"'{int}' is not a valid person ID"
                , int => $value;
        $value = undef if !$value; # Can be empty string, generating warnings
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

sub clear
{   my $self = shift;
    $self->clear_email;
    $self->clear_username;
    $self->clear_firstname;
    $self->clear_surname;
    $self->clear_freetext1;
    $self->clear_freetext2;
    $self->clear_organisation;
    $self->clear_department;
    $self->clear_team;
    $self->clear_title;
    $self->clear_text;
}

has schema => (
    is       => 'rw',
    required => 1,
);

has value_hash => (
    is      => 'rwp',
    lazy    => 1,
    builder => sub {
        my $self = shift;
        $self->has_init_value or return;
        # May or may not be multiple values, depending on source. Could have
        # come from a record value (multiple possible) or from a record
        # property such as created_by
        my $init_value = $self->init_value;
        my $value = ref $init_value eq 'ARRAY'
            ? $init_value->[0]
            : $init_value;
        if (ref $value eq 'HASH')
        {
            # XXX - messy to account for different initial values. Can be tidied once
            # we are no longer pre-fetching multiple records
            $value = $value->{value} if exists $value->{record_id};
            my $id = $value->{id};
            $self->has_id(1) if defined $id || $self->init_no_value;
            return +{
                id            => $id,
                email         => $value->{email},
                username      => $value->{username},
                firstname     => $value->{firstname},
                surname       => $value->{surname},
                freetext1     => $value->{freetext1},
                freetext2     => $value->{freetext2},
                organisation  => $value->{organisation},
                department    => $value->{department},
                department_id => $value->{department_id},
                team          => $value->{team},
                team_id       => $value->{team_id},
                title         => $value->{title},
                value         => $value->{value},
            };
        }
        else {
            return $self->column->id_to_hash($value);
        }
    },
);

# Whether to allow deleted users to be set
has allow_deleted => (
    is => 'rw',
);

sub email     { $_[0]->value_hash && $_[0]->value_hash->{email} }
sub username  { $_[0]->value_hash && $_[0]->value_hash->{username} }
sub firstname { $_[0]->value_hash && $_[0]->value_hash->{firstname} }
sub surname   { $_[0]->value_hash && $_[0]->value_hash->{surname} }
sub freetext1 { $_[0]->value_hash && $_[0]->value_hash->{freetext1} }
sub freetext2 { $_[0]->value_hash && $_[0]->value_hash->{freetext2} }

sub _from_vh($$$)
{   my ($self, $table, $key, $id_key) = @_;
    my $vh = $self->value_hash or return;

      ref $vh->{$key} ? $vh->{$key}
    : $vh->{$id_key}  ? $::db->get_record($table => $vh->{$id_key})
    : undef;
}

has organisation => (
    is      => 'lazy',
    # id not with _id!!!
    builder => sub { $_[0]->_from_vh(Organisation => 'organisation', 'organisation') },
);

has department => (
    is      => 'lazy',
    builder => sub { $_[0]->_from_vh(Department => 'department', 'department_id') },
);

has team => (
    is      => 'lazy',
    builder => sub { $_[0]->_from_vh(Team => 'team', 'team_id') },
);

has title => (
    is      => 'lazy',
    builder => sub { $_[0]->_from_vh(Title => 'title', 'title_id') },
);

sub search_values_unique { [ shift->text ] }

has text => (
    is      => 'lazy',
    builder => sub { $_[0]->value_hash && $_[0]->value_hash->{value} },
);

has id => (
    is      => 'rw',
    lazy    => 1,
    trigger => sub {
        my ($self, $value) = @_;
        $self->_set_value_hash($self->column->id_to_hash($value));
    },
    builder => sub { $_[0]->value_hash && $_[0]->value_hash->{id} },
);

has has_id => (
    is  => 'rw',
    isa => Bool,
);

sub ids        { [ $_[0]->id ] }
sub value      { $_[0]->id }
sub is_blank   { ! $_[0]->id }
sub as_string  { $_[0]->text // "" }
sub as_integer { $_[0]->id // 0 }

# Make up for missing predicated value property
sub has_value  { $_[0]->has_id }

around 'clone' => sub {
    my $orig = shift;
    my $self = shift;
    $orig->($self,
        id           => $self->id,
        email        => $self->email,
        username     => $self->username,
        schema       => $self->schema,
        firstname    => $self->firstname,
        surname      => $self->surname,
        freetext1    => $self->freetext1,
        freetext2    => $self->freetext2,
        organisation => $self->organisation,
        department   => $self->department,
        team         => $self->team,
        title        => $self->title,
        text         => $self->text,
        @_,
    );
};


sub _build_for_code
{   my $self = shift;
    +{
        surname      => $self->surname,
        firstname    => $self->firstname,
        email        => $self->email,
        freetext1    => $self->freetext1,
        freetext2    => $self->freetext2,
        organisation => $self->organisation,
        department   => $self->department,
        team         => $self->team,
        title        => $self->title,
        text         => $self->text,
    };
}

1;

