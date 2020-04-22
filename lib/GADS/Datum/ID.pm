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

package GADS::Datum::ID;

use Log::Report 'linkspace';
use Moo;

extends 'GADS::Datum';

has value => (
    is      => 'lazy',
    builder => sub { $_[0]->current_id },
);

sub is_blank   { ! $_[0]->value }
sub as_string  { $_[0]->value }
sub as_integer { $_[0]->value || undef }

sub _build_for_code
{   my $self = shift;
    $self->as_integer;
}

1;

