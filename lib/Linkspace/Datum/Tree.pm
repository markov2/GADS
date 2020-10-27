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

use warnings;
use strict;

package Linkspace::Datum::Tree;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

sub hash_value($)
{   my ($self, $column) = @_;
    my $node_id = $self->value;
    +{ id => $node_id, text => $column->node($node_id)->name };
}

sub full_path { $_[0]->as_string }
sub value_regex_test { shift->full_path }

sub _value_for_code($$$)
{   my ($self, $column, $node_id) = @_;
    my $node = $column->node($node_id) or panic;

    my (%parents, $count);
    foreach my $parent (reverse $node->ancestors)
    {   # Use text for the parent number, as this will not work in Lua:
        # node.parents.1  hence  node.parents.parent1
        #XXX does it need an extra HASH level?  node.parent1?
        $parents{'parent'.++$count} = $parent->id;
    }

     +{ value   => $node->name, parents => \%parents };
}

1;
