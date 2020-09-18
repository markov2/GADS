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

package Linkspace::Column::Intgr;
# Extended by ::Id

use Log::Report 'linkspace';
use Linkspace::Util qw/flat/;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Column';

my @options = (
    show_calculator => 0,
);

###
### META
###

__PACKAGE__->register_type;

sub addable        { 1 }
sub can_multivalue { 1 }
sub option_defaults { shift->SUPER::option_defaults(@_, @options) }
sub return_type    { 'integer' }
sub value_table    { 'Intgr' }

###
### Class
###

sub remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Intgr => { layout_id => $col_id });
}

###
### Instance
###

sub is_numeric      { 1 }
sub show_calculator { $_[0]->options->{show_calculator} }

sub _is_valid_value($)
{   my ($self, $value) = @_;
    return $1 if $value =~ /^\s*([+-]?[0-9]+)\s*$/;

    error __x"'{int}' is not a valid integer for '{col}'",
       int => $value, col => $self->name;
}

sub import_value
{   my ($self, $value) = @_;

    $::db->create(Intgr => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => $value->{value},
    });
}

1;

