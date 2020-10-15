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

package Linkspace::Column::Person;
# Extended by ::CreatedBy ::Deletedby

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Column';

use Log::Report 'linkspace';
use Linkspace::Util qw/flat/;

my @options = (
    default_to_login => 0,
);

my @person_properties = qw/
   id email username firstname surname freetext1 freetext2
   organisation_id department_id team_id title_id value/;

###
### META
###

__PACKAGE__->register_type;

sub has_filter_typeahead { 1 }
sub has_fixedvals   { 1 }
sub option_defaults { shift->SUPER::option_defaults(@_, @options) }
sub retrieve_fields { \@person_properties }
sub sprefix         { 'value' }
sub tjoin           { +{ $_[0]->field => 'value' } }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Person => { layout_id => $col_id });
}

sub person_properties    { @person_properties }

###
### Instance
###

sub default_to_login { $_[0]->_options->{default_to_login} }

# Convert based on whether ID or full name provided
sub value_field_as_index
{   my ($self, $value) = @_;

    my $type;
    foreach (flat $value)
    {   $type = /^[0-9]*$/ ? 'id' : $self->value_field;
        last if $type ne 'id';
    }

    $type;
}

sub people { $_[0]->site->users->all_users }
sub resultset_for_values { $_[0]->people }

sub id_as_string
{   my ($self, $user_id) = @_;
    my $person = $self->site->users->user($user_id) or return '';
    $person->fullname;
}

sub import_value
{   my ($self, $value) = @_;

    $::db->create(Person => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => $value->{value},
    });
}

sub _is_valid_value($)
{   my ($self, $value) = @_;

    (my $person_id) = $value =~ /^\s*([0-9]+)\s*$/
        or error __x"'{int}' is not a valid id of a person for '{col.name}'",
            int => $value, col => $self;

    $self->site->users->user($person_id)
        or error __x"Person {int} is not found for '{col.name}'",
            int => $value, col => $self;

    $person_id;
}



1;

