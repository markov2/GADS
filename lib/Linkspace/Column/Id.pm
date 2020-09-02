=pod
GADS - Globally Accessible Data Store
Copyright (C) 2019 Ctrl O Ltd

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

package Linkspace::Column::Id;

use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Column::Intgr';

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue   { 0 }
sub is_internal_type { 1 }
sub is_userinput { 0 }
sub value_table  { 'Current' }
sub value_field  { 'id' }

###
### Instance
###

sub _is_valid_value
{   my ($self, $value) = @_;
    return $1 if $value =~ /^\s*([0-9]+)\s*$/ && $1 != 0;
    error __x"'{id}' is not a valid ID", id => $value;
}

sub sprefix      { 'current' }
sub tjoin        {}

1;

