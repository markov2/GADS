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

package Linkspace::Column::String;

use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column';

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue      { 1 }
sub form_extras         { [ qw/is_textbox force_regex/ ], [] }
sub has_multivalue_plus { 1 }

###
### Class
###

sub remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(String => { layout_id => $col_id });
}

###
### Instance
###

sub string_storage { 1 }

sub resultset_for_values
{   my $self = shift;
    $::db->search(String => { layout_id => $self->id }, { group_by => 'me.value' });
}

before import_hash => sub {
    my ($self, $values, %options) = @_;
    my $is_textbox = $values->{is_textbox};
    notice __x"Update: textbox from {old} to {new}", old => $self->is_textbox, new => $is_textbox
        if $self->is_textbox != $is_textbox;

    my $force_regex = $values->{force_regex} // '';
    notice __x"Update: force_regex from {old} to {new}", old => $self->force_regex, new => $force_regex
        if +($self->force_regex || '') ne $force_regex;
};

sub export_hash
{   my $self = shift;
    $self->SUPER::export_hash(@_,
        is_textbox  => $self->is_textbox,
        force_regex => $self->force_regex,
    );
}

sub import_value
{   my ($self, $value) = @_;

    $::db->create(String => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => $value->{value},
        value_index  => $value->{value_index},
    });
}

sub field_values($;$%)
{   my ($self, $datum) = @_;
    my $values = $datum->values;

    # No values, but still need to write null value
    map +{ value => $_, 
           value_index => defined ? (lc substr $_, 0, 128) : '',
         }, @$values ? @$values : (undef);
}

1;

