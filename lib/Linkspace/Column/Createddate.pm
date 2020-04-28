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

package Linkspace::Column::Createddate;

use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column::Date';

###
### META
###

INIT { __PACKAGE__->register_type }

sub internal     { 1 }
sub table        { 'Record' }
sub tjoin        {}
sub userinput    { 0 }
sub value_field  { 'created' }

sub include_time { 1 }

###
### Instance
###

sub sprefix      { 'record' }

1;

