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

package Linkspace::Column::Tree;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Column';

use JSON qw(decode_json encode_json);
use Log::Report 'linkspace';
use Tree::DAG_Node;

###
### META
###

__PACKAGE__->register_type;

sub db_field_extra_export { [ 'end_node_only' ] }
sub can_multivalue  { 1 }
sub has_fixedvals   { 1 }
sub form_extras     { [ 'end_node_only' ], [] }
sub has_filter_typeahead { 1 }
sub retrieve_fields { [ qw/id value/ ] }
sub value_table     { 'Enum' }

###
### Class
###

sub remove_column($)
{   my $col_id = $_[1]->id;
    my %col_ref = (layout_id => $_[0]->id);
    $::db->update(Enumval => \%col_ref, {parent => undef});  #XXX two way ref?
    $::db->delete(Enum    => \%col_ref);
    $::db->delete(Enumval => \%col_ref);
}

###
### Instance
###

#XXX at assignment, /\D/ must translate names into numval ids

sub sprefix { 'value' }
sub tjoin   { +{ $_[0]->field => 'value' } }
sub value_field_as_index { 'id' }

sub DESTROY
{   my $self = shift;
    $self->_root->delete_tree if $self->_has_tree;
}

# The root node, which all other nodes are referenced from.
# Gets value from _tree once it's built
sub _root { $_[0]->_tree->{root} }

# A hash of all the tree nodes. Also gets value from
# _tree once it's built. Contains only DAG_Node nodes
sub _nodes { $_[0]->_tree->{nodes} }

# An array of all the enumvals. Also gets value from
# _tree once it's built. Contains the enumvals with
# their actual values in, but no tree relationship info
has enumvals => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
    
        my $enumvals = $::db->search(Enumval => {
            layout_id => $self->id,
        },{
            order_by => 'me.value',
            result_class => 'HASH',
        });
        [ $enumvals->all ];
    },
);

has _enumvals_index => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my %enumvals = map +($_->{id} => $_), @{$self->enumvals};
        \%enumvals;
    },
);

sub id_as_string
{   my ($self, $id) = @_;
    my $node = $self->node($id) or return '';
    $node->{value};
}

sub string_as_id
{   my ($self, $value) = @_;
    my $rs = $::db->search(Enumval => {
        layout_id => $self->id,
        deleted   => 0,
        value     => $value,
    });
    error __x"More than one value for {value} in field {name}", value => $value, name => $self->name
        if $rs->count > 1;
    error __x"Value {value} not found in field {name}", value => $value, name => $self->name
        if $rs->count == 0;
    return $rs->next->id;
}

# The whole tree, constructed here so that it only
# needs to be done once
has _tree => (
    is        => 'rw',
    lazy      => 1,
    clearer   => 1,
    builder   => 1,
    predicate => 1,
);

after build_values => sub {
    my ($self, $original) = @_;
    $self->original($original);
    $self->end_node_only($original->{end_node_only});
};

sub write_special
{   my ($self, %options) = @_;
    my $rset = $options{rset};
    $rset->update({
        end_node_only => $self->end_node_only,
    });
    return ();
};

sub _is_valid_value($)
{   my ($self, $value) = @_;

    my $node = $self->node($value)
        or error __x"Node '{int}' is not a valid tree node ID for '{col.name}'",
            int => $value, col => $self;

    if($node->{node}->{attributes}->{deleted})
    {   error __x"Node '{int}' has been deleted and can therefore not be used",
            int => $value;
    }
    1;
}

# Get a single node value
sub node
{   my ($self, $id) = @_;
    $id or return;

    my $node = $self->_nodes->{$id} or return;
     +{ id    => $id,
        node  => $node,
        value => $self->_enumvals_index->{$id}->{value},
      };
}

has ancestors => (
    lazy    => 1,
    builder => sub {
        my $self = shift;
        my @return;
        foreach my $node_id (@{$self->ids})
        {   my $node = $self->node($node_id);
            my @ancestors = $node->{node} ? $node->{node}{node}->ancestors : ();
            my @ancs;
            foreach my $anc (@ancestors)
            {   my $node     = $self->node($anc->name);
                my $dag_node = $node->{node}{node};
                push @ancs, $node if $dag_node && defined $dag_node->mother; # Do not add root node
            }
            push @return, \@ancs;
        }
        \@return;
    },
);

sub _build__tree
{   my $self = shift;

    my $enumvals;
    my $tree = {};
    my @order;
    my @enumvals = @{$self->enumvals};
    foreach my $enumval (@enumvals)
    {
        # If a node is deleted then still add to the tree, in case it is still
        # in use and needed for things like code evaluation. However, don't add
        # it in the tree with a parent, just have it "loose"
        my $parent = !$enumval->{deleted} && $enumval->{parent}; # && $enum->parent->id;

        my $node = Tree::DAG_Node->new();
        $node->name($enumval->{id});
        $tree->{$enumval->{id}} = {
            node       => $node,
            parent     => $parent,
            attributes => {
                deleted => $enumval->{deleted},
            },
        };
        # Keep order in a list
        push @order, $enumval->{id};
        # Store the entire value for retrieval later
        $enumvals->{$enumval->{id}} = $enumval;
    }

    my $root = Tree::DAG_Node->new();
    $root->name('Root');

    foreach my $n (@order)
    {   my $node = $tree->{$n};
        if(my $parent = $node->{parent})
        {   $tree->{$parent}->{node}->add_daughter($node->{node});
        }
        else
        {   $root->add_daughter($node->{node});
        }
    }

     +{
        nodes    => $tree,
        root     => $root,
        enumvals => $enumvals,
      };
}

sub to_hash
{   my ($self, @selected) = @_;

    my %selected = map +($_ => 1), @selected;

    my $stash = {
        tree => {
            text     => 'root',
            children => [],
        },
    };

    my $root = $self->_root;
    return [] unless $root->depth_under; # No nodes
    my $enumvals = $self->_enumvals_index;

    $root->walk_down
    ({
        callback => sub
        {   my($node, $options) = @_;

            my $depth = $options->{_depth};
            if($depth == 0)
            {   # Starting out at root
                $options->{stash}{last_node}{$depth} = $stash->{tree};
                return 1;
            }

            $enumvals->{$node->name}->{deleted} # Ignore deleted nodes
                and return 1;

            my %leaf   = (
                id   => $node->name,
                text => $enumvals->{$node->name}->{value}, 
            );
            $leaf{state} = { selected => \1 } if $selected{$node->name};

            my $parent = $options->{stash}{last_node}{$depth-1};
            push @{$parent->{children}}, \%leaf;
            $options->{stash}{last_node}{$depth} = $parent->{children}[-1];

            return 1; # Keep walking.
        },
        _depth => 0,
        stash  => $stash,
    });
    $stash->{tree}{children};
}

sub _delete_unused_nodes
{   my ($self, %options) = @_;

    # Get all ones currently in database. This will be different to
    # the ones currently in _enumvals_index
    my @all_nodes = $::db->search(Enumval => { layout_id => $self->id },
       { result_class => 'HASH' }
    )->all;

    my @top = grep !$_->{parent}, @all_nodes;

    sub _flat
    {
        my ($self, $start, $flat, $level, @all_nodes) = @_;
        push @$flat, {
            id      => $start->{id},
            level   => $level,
            deleted => $start->{deleted},
            parent  => $start->{parent},
        };
        # See if it has any children
        my @children = grep { $_->{parent} && $_->{parent} == $start->{id} } @all_nodes;
        _flat($self, $_, $flat, $level + 1, @all_nodes) for @children;
    };

    # Now collect all the nodes in a flat structure. We can only delete
    # from the children up, otherwise there are relationship constraints.
    # We actually only delete nodes that aren't referenced anywhere, in
    # order to keep data integrity for old records
    my $flat = [];
    _flat $self, $_, $flat, 0, @all_nodes for @top;

    my @flat = sort { $b->{level} <=> $a->{level} } @$flat;

    # Do the actual deletion if they don't exist
    foreach my $node (@flat)
    {   next if $node->{deleted}; # Already deleted

        if($self->_enumvals_index->{$node->{id}})
        {
            # Node in use somewhere
            if ($node->{parent}
                && (!$self->_enumvals_index->{$node->{parent}} || $self->_enumvals_index->{$node->{parent}}->{deleted})
            )
            {
                # Current node still exists, but its parent doesn't
                # Move current node to the top by undefing the parent
                $::db->update(Enumval => $node->{id}, {parent => undef});
            }
        }
        else
        {
            my $count = $self->schema->resultset('Enum')->search({
                layout_id => $self->id,
                value     => $node->{id}
            })->count; # In use somewhere
            my $haschild = grep {$_->{parent} && $node->{id} == $_->{parent}} @flat; # Has (deleted) children
            if ($count || $haschild)
            {
                $self->schema->resultset('Enumval')->find($node->{id})->update({
                    deleted => 1
                });
            }
            else
            {   $self->schema->resultset('Enumval')->find($node->{id})->delete;
            }
        }
    }
}

sub random
{   my $self = shift;
    my %hash = %{$self->_enumvals_index};
    my $value;
    while (!$value)
    {
        my $node = $hash{(keys %hash)[rand keys %hash]};
        $value = $node->{value} unless $node->{deleted};
    }
    $value;
}

sub update
{   my ($self, $tree, %params) = @_;

    # Create a new hash ref with our new tree structure in. We'll copy
    # the new nodes into it as we go, and then compare it to the old
    # one after to know which ones to delete from the database
    my $new_tree = {};

    # Do any updates
    $self->_update($_, $new_tree, %params) for @$tree;
    $self->_set__enumvals_index($new_tree);
    $self->_delete_unused_nodes;
}

sub _update
{   my ($self, $t, $new_tree, %params) = @_;

    my $parent = $t->{parent} || '#';
    $parent = undef if $parent eq '#'; # Hash is top of tree (no parent)

    my $enum_mapping = $params{enum_mapping};
    my $source_id    = delete $t->{source_id};

    my $tid = is_valid_id $t->{id};
    my $dbt = $tid ? $self->_enumvals_index->{$tid} : undef;

    if($dbt)
    {   if($dbt->{value} ne $t->{text})
        {   $::db->update(Enumval => $tid, {
                parent => $parent,
                value  => $t->{text},
            });

            $enum_mapping->{$source_id} = $tid
                if $enum_mapping;
        }
        $new_tree->{$dbt->{id}} = $dbt;
    }
    else
    {   # new entry
        $dbt = {
            layout_id => $self->id,
            parent    => $parent,
            value     => $t->{text},
        };
        my $id = $::db->create(Enumval => $dbt);
        $dbt->{id} = $id;

        # Add to existing cache.
        $new_tree->{$id} = $dbt;
        $enum_mapping->{$source_id} = $id
            if $enum_mapping;
    }

    foreach my $child (@{$t->{children}})
    {   $child->{parent} = $dbt->{id};
        $self->_update($child, $new_tree, %params);
    }
};

sub resultset_for_values
{   my $self = shift;
    if ($self->end_node_only)
    {
        $::db->search(Enumval => {
            'me.layout_id' => $self->id,
            'me.deleted'   => 0,
            'enumvals.id'  => undef,
        },{
            join => 'enumvals',
        });
    }
    else
    {   $::db->search(Enumval => {
            layout_id => $self->id,
            deleted   => 0,
        });
    }
}

sub _import_branch
{   my ($self, $old_in, $new_in, %options) = @_;
    my $report = $options{report_only};
    my @old = sort { $a->{text} cmp $b->{text} } @$old_in;
    my @new = sort { $a->{text} cmp $b->{text} } @$new_in;
    my @to_write;
    while (@old)
    {
        my $old = shift @old;
        my $new = shift @new;
        # If it's the same, easy, onto the next one
        if ($old->{text} && $new->{text} && $old->{text} eq $new->{text})
        {
            trace __x"No change for tree value {value}", value => $old->{text}
                if $report;
            $new->{source_id} = $new->{id};
            $new->{id} = $old->{id};
            push @to_write, $new;
        }
        # Different. Is the next one the same?
        elsif ($old[0] && $new[0] && $old[0]->{text} eq $new[0]->{text})
        {
            # Yes, assume the previous is a value change
            notice __x"Changing tree value {old} to {new}", old => $old->{text}, new => $new->{text}
                if $report;
            $new->{source_id} = $new->{id};
            $new->{id} = $old->{id};
            push @to_write, $new;
        }
        # Is the next new one the same as the current old one?
        elsif ($new[0] && $old->{text} eq $new[0]->{text})
        {
            # Yes, assume new value
            notice __x"Adding tree value {new}", new => $new->{text}
                if $report;
            $new->{source_id} = delete $new->{id};
            push @to_write, $new;
            # Add old one back onto stack for processing next loop
            unshift @old, $old;
        }
        elsif ($options{force})
        {
            if ($new->{text})
            {
                notice __x"Unknown treeval update {value}, forcing as requested", value => $new->{text};
                $new->{source_id} = delete $new->{id};
                push @to_write, $new;
            }
            else {
                notice __x"Treeval {value} appears to no longer exist, force removing as requested", value => $old->{text};
            }
        }
        else {
            # Different, don't know what to do, require manual intervention
            if ($report)
            {
                notice __x"Error: don't know how to handle tree updates for {name}, manual intervention required."
                    ." (failed at old {old} new {new})", name => $self->name, old => $old->{text}, new => $new->{text};
                return;
            }
            else {
                error __x"Error: don't know how to handle tree updates for {name}, manual intervention required"
                    ." (failed at old {old} new {new}, column {column})", name => $self->name, old => $old->{text}, new => $new->{text},
                    column => $self->name;
            }
        }
        if ($new->{children} && @{$new->{children}})
        {
            $new->{children} = [$self->_import_branch($old->{children}, $new->{children}, %options)];
        }
    }
    # Add any remaining new ones
    delete $_->{id} for @new;

    (@to_write, @new);
}

sub import_after_write
{   my ($self, $values, %options) = @_;
    my @new = @{$values->{tree}};

    my @to_write;
    # Same as enumval: We have no unqiue identifier with which to match, so we
    # have to compare the new and the old lists to try and work out what's
    # changed. Simple changes are handled automatically, more complicated ones
    # will require manual intervention
    if (my @old = @{$self->json})
    {   @to_write = $self->_import_branch(\@old, \@new, %options);
    }
    else
    {   sub _to_source {
            foreach (@_)
            {
                $_->{source_id} = delete $_->{id};
                _to_source(@{$_->{children}})
                    if $_->{children};
            }
        }
        _to_source(@new);
        @to_write = @new;
    }

    $self->update(\@to_write, %options);
}

sub export_hash
{   my $self = shift;
    my $h = $self->SUPER::export_hash(@_);
    $h->{tree} = $self->to_hash;
    $h;
}

sub import_value
{   my ($self, $value) = @_;

    $::db->create(Enum => {     #XXX?
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => $value->{value},
    });
}

1;

