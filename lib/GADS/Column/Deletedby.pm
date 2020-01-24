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

package Linkspace::Column::Deletedby;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column::Person';

use Log::Report 'linkspace';

###
### META
###

__PACKAGE__->register_type;

sub hidden      { 1 }
sub internal    { 1 }
sub table       { 'Current' }
sub userinput   { 0 }
sub value_field { 'deletedby' }

###
### Instance
###

sub sprefix     { 'current' }
sub tjoin       { 'deletedby' }

1;
