## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Person;
# Extended by ::CreatedBy ::Deletedby

use Log::Report 'linkspace';
use Linkspace::Util qw(flat);
use Scalar::Util    qw(blessed);

use Moo;
extends 'Linkspace::Column';

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

sub datum_class      { 'Linkspace::Datum::Person' }
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
sub datum_as_string { my $p = $_[1]->person; $p ? $p->fullname : undef }

sub is_valid_value($)
{   my ($self, $value) = @_;

    return $value->id
        if blessed $value && $value->isa('Linkspace::User');

    (my $person_id) = $value =~ /^\s*([0-9]+)\s*$/
        or error __x"'{int}' is not a valid id of a person for '{col.name}'",
            int => $value, col => $self;

    $self->site->users->user($person_id)
        or error __x"Person {int} is not found for '{col.name}'",
            int => $value, col => $self;

    $person_id;
}

1;
