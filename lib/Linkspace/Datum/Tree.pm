## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use warnings;
use strict;

package Linkspace::Datum::Tree;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum::Enum';

sub _unpack_values($$$%)
{   my ($class, $column, $old_datums, $values, %args) = @_;

warn "UNPACK VALUES";
    my @nodes;
    foreach my $value (@$values)
    {   warn $value;
    }

    $values;
}

sub hash_value($)
{   my ($self, $column) = @_;
    +{ id => $self->value, text => $column->datum_as_string($self) };
}

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

sub node        { $_[0]->column->node($_[0]->value) }
sub full_path   { $_[0]->node->path }
sub match_value { $_[0]->node->path }

1;
