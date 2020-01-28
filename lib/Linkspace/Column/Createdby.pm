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

package Linkspace::Column::Createdby;

use Log::Report     'linkspace';
use List::Util      qw/uniq/;
use Linkspace::Util qw/index_by_id/;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column::Person';
use namespace::clean;

###
### META
###

__PACKAGE__->register_type;

sub internal  { 1 }
sub userinput { 0 }

###
### Instance
###

sub sprefix() { 'createdby' }
sub tjoin     { 'createdby' }

# Different to normal function, this will fetch users when passed a list of IDs
sub fetch_multivalues
{   my ($self, $victim_ids) = @_;
    $victim_ids && @$victim_ids or return +{ };

    my $users = $self->site->users;
    index_by_id [ map $users->user($_), uniq @$victim_ids ];
}

1;
