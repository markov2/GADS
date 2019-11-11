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

package GADS::Column::Person;
extends 'GADS::Column';

use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

our @person_properties = qw/
   id email username firstname surname freetext1 freetext2
   organisation department_id team_id title value/;

# Convert based on whether ID or full name provided
sub value_field_as_index
{   my ($self, $value) = @_;

    my $type;
    foreach (ref $value eq 'ARRAY' ? @$value : $value)
    {   $type = /^[0-9]*$/ ? 'id' : $self->value_field;
        last if $type ne 'id';
    }

    $type;
}

has '+has_filter_typeahead' => (
    default => 1,
);

has '+fixedvals' => (
    default => 1,
);

has '+option_names' => (
    default => sub { [ 'default_to_login' ] },
);

sub _build_retrieve_fields
{   my $self = shift;
    \@person_properties;
}

has default_to_login => (
    is      => 'rw',
    isa     => Bool,
    lazy    => 1,
    coerce  => sub { $_[0] ? 1 : 0 },
    builder => sub {
        my $self = shift;
        $self->has_options ? $self->options->{default_to_login} : 0;
    },
    trigger => sub { $_[0]->reset_options },
);

sub _build_sprefix { 'value' };

sub people { $_[0]->site->users->all }

sub id_as_string
{   my ($self, $id) = @_;
    my $person = $::session->site->users->get_user(id => $id)
        or return '';
    $person->value;
}

after build_values => sub {
    my ($self, $original) = @_;

    if(my $file_option = $original->{file_options}->[0])
    {
        $self->file_options({ filesize => $file_option->{filesize} });
    }
};

sub tjoin
{   my $self = shift;
    +{ $self->field => 'value' };
}

sub random   #XXX still in use?
{   my $self = shift;
    my @people = $self->people;
    $people[rand @people]->value;
}

sub resultset_for_values
{   $::session->site->users->search_active;
}

sub cleanup
{   my ($class, $schema, $id) = @_;
    $::session->site->delete(Person => { layout_id => $id });
}

sub import_value
{   my ($self, $value) = @_;

    $::session->site->create(Person => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => $value->{value},
    });
}

1;

