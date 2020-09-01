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

package Linkspace::Column::Serial;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column';

use Log::Report 'linkspace';

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue { 1 }
sub is_internal_type { 1 }
sub is_addable   { 1 }
sub return_type  { 'integer' }
sub is_userinput { 0 }

sub value_table  { 'Current' }
sub value_field  { 'serial' }

###
### Class
###

###
### Instance
###

sub _is_valid_value { $_[1] =~ /^\s*([0-9]+)\s*$/ && $1 != 0 ? $1 : undef }

sub sprefix     { 'current' }
sub tjoin       {}
sub is_numeric  { 1 }

1;

