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

my @option_names      = qw/default_to_login/;

my @person_properties = qw/
   id email username firstname surname freetext1 freetext2
   organisation_id department_id team_id title_id value/;

###
### META
###

__PACKAGE__->register_type;

sub has_filter_typeahead { 1 }
sub has_fixedvals        { 1 }
sub option_names         { shift->SUPER::option_names(@_, @options_names) }
sub retrieve_fields      { \@person_properties }

### Specific to Person

sub person_properties    { @person_properties }

###
### Class
###

sub remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Person => { layout_id => $col_id });
}

###
### Instance
###

sub sprefix { 'value' }
sub tjoin   { +{ $_[0]->field => 'value' } }
sub default_to_login     { $_[0]->options->{default_to_login} }

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

sub people { $_[0]->site->users->all_users }
sub resultset_for_values { $self->people }

sub id_as_string
{   my ($self, $id) = @_;
    my $person = $self->site->users->user($user_id) or return '';
    $person->value;
}

after build_values => sub {
    my ($self, $original) = @_;

    if(my $file_option = $original->{file_options}->[0])
    {   $self->file_options({ filesize => $file_option->{filesize} });
    }
};


sub import_value
{   my ($self, $value) = @_;

    $::db->create(Person => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => $value->{value},
    });
}

1;

