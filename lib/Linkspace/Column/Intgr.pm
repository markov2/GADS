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

my @option_names = qw/show_calculator/;

###
### META
###

__PACKAGE__->register_type;

sub value_table  { 'Intgr' }
sub addable      { 1 }
sub return_type  { 'integer' }
sub option_names { shift->SUPER::option_names, @option_names }

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

sub is_valid_value($%)
{   my ($self, $values, %options) = @_;

    foreach my $v (flat $values)
    {   if($v && $v !~ /^-?[0-9]+$/)
        {   return 0 unless $options{fatal};
            error __x"'{int}' is not a valid integer for '{col}'",
                int => $v, col => $self->name;
        }
    }

    1;
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

