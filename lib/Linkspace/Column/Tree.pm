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
use Log::Report 'linkspace';

use Scalar::Util    qw(weaken);
use List::MoreUtils qw(part);

use Linkspace::Util qw(index_by_id is_valid_id);

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Column::Enum';

#XXX Enumval is not cleanly wrapped as Linkspace::DB::Table, but has a serious
#XXX problem with column 'parent' (which should have been named 'parent_id') and
#XXX the relation 'parent' which it defined.  Hence $ev->parent returns an object,
#XXX not the id.  Fix this dirty:
{   no strict 'refs';
    use GADS::Schema::Result::Enumval;
    *GADS::Schema::Result::Enumval::parent_id
       = sub { $_[0]->{_column_data}{parent} };
}

###
### META
###

__PACKAGE__->register_type;

sub db_field_extra_export { [ 'end_node_only' ] }
sub form_extras     { [ qw/end_node_only tree/ ], [] }
sub retrieve_fields { [ qw/id value/ ] }
sub value_table     { 'Enum' }

sub sprefix { 'value' }
sub tjoin   { +{ $_[0]->field => 'value' } }
sub value_field_as_index { 'id' }

###
### Instance
###

sub _column_extra_update($%)
{   my ($self, $extra, %args) = @_;
    $self->SUPER::_column_extra_update($extra, %args);

    if($self->end_node_only)
    {   # We can only switch to 'end_node_only' mode when none of the
        # intermediate nodes is in use.  However, at the moment we cannot
        # detect whether the field actually changes because the flags has
        # already been updated.  Well, tree changes are rare.

        $_->walk( sub {
           my $node = shift;
           return 1 if $self->is_leaf || ! $self->enumval_in_use($node->id);

           error __x"Cannot switch to 'End Node Only' because non-end node '{node.name}' is in use.",
               node => $node;
        }) for $self->_tops;
    }

    if(my $other = delete $extra->{tree})
    {   if(my $map = delete $args{import_tree})
             { $self->_import_tree($other, $map, %args) }
        else { $self->_update_tree($other, %args) }
    }

    $self;
}

sub _is_valid_value($)
{   my ($self, $value) = @_;

    my $node = $self->node($value)
        or error __x"Node '{value}' is not a valid tree node for '{col.name}'",
            value => $value, col => $self;

    ! $node->is_deleted
        or error __x"Node '{node.name}' has been deleted and can therefore not be used",
            node => $node;

    $self->end_node_only || $node->is_leaf
        or error __x"Node '{node.name}' cannot be used: not a leaf node", node => $node;

    $value;
}

sub _as_string(%)
{   my ($self, %args) = @_;
    my $mark_leafs = $self->end_node_only;
    my @lines;
    $_->walk(sub {
       my ($node, $level) = @_;
       push @lines, sprintf "%s%s%s %s",
           ($node->is_deleted ? 'D' : ' '),
           ($mark_leafs && $node->is_leaf ? '*' : ' '),
           '    ' x ($level-1),
           $node->name;
    }) for $self->_tops;
    join "\n", @lines;
}

sub _values_beginning_with($%)
{   my ($self, $start, %args) = @_;
    my @path    = split m!\s*/\s*!, $start;
    pop @path if @path && ! length $path[-1];
    my $partial = @path ? pop @path : undef;
    my $parent  = $self->tree->find(@path) or return [];

    my @hits    = grep $_->name =~ /^\Q$partial/, $parent->children;
    [ map +{ id => $_->id, name => $_->path }, @hits ];
}

=head2 my $tree = $column->tree;
The selection tree as structured nodes, which are C<::Column::Tree::Node> instances
(implemented in the same source file)  The root element on top is used to group
the possible existence of multiple trees.
=cut

has tree => (is => 'rw', lazy => 1, builder => '_build_tree');

sub _build_tree
{   my $self  = shift;
    my $enumvals = $self->enumvals(include_deleted => 1, order => 'asc');
#warn "BUILD TREE";
    my @nodes = map Linkspace::Column::Tree::Node->new(enumval => $_), @$enumvals;
    my $nodes = index_by_id @nodes;

#warn "ID=", $_->id, " NAME=", $_->value, " PARENT=", $_->parent_id, "\n"
#   for map $_->enumval, @nodes;

    my ($tops, $leafs) = part { $_->enumval->parent_id ? 1 : 0 } @nodes;
#warn @{$tops || []}.' tops, leafs='.@{$leafs || []};
    $nodes->{$_->enumval->parent_id}->add_child($_)
        for sort { $a->name cmp $b->name } @{$leafs || []};
#warn $_->id, ": ", join ',', $_->children, "\n" for @nodes;

    Linkspace::Column::Tree::Node->new(name => 'Root', children => $tops);
}

sub _tops() { $_[0]->tree->children }

=head2 my $node = $column->node($node_id);
Returns a single node from the tree: returns a ::Node object.  Use C<$node->enumval>
to get to its database record.  Node names are only unique per parent, so names cannot
be used globally.
=cut

sub node($)
{   my ($self, $node_id) = @_;
    my $result;
    $self->tree->walk(
       sub { !$_[0]->is_root && $_[0]->id==$node_id or return 1; $result = $_[0]; 0 });
    $result;
}

=head2 \%h = $column->to_hash(%options);
Returns the structure the tree as nested HASHes.
=cut

#XXX this is an ARRAY of the tops.  Do we need the root element.
sub to_hash
{   my ($self, %args) = @_;

    my $selected_ids = $args{selected_ids} || [];
    my %is_selected  = map +($_ => 1), @$selected_ids;

    # Children are passed one level up via this array of "returned per level"
    # hashes.  So, $level_childs[3] contains the children to of the currently
    # being constructed parent on level 3.
    my @level_childs;

    $_->walk_depth_first(sub
      { my ($node, $level) = @_;
        my $enumval = $node->enumval;
        my $childs  = delete $level_childs[$level] || [];

        my %def = (
            id       => $enumval->id,
            text     => $enumval->value, 
        );
        $def{children} = $childs if @$childs;
        $def{state}    = { selected => \1 } if $is_selected{$enumval->id};
        push @{$level_childs[$level-1]}, \%def;

      }) for $self->_tops;

    $level_childs[0];
}

=head2 $column->delete_unused_enumvals;
Remove all enumvals from the database which are flagged 'deleted' and also
not in use by any (historic) row revision.
=cut

sub delete_unused_enumvals(%)
{   my ($self, %args) = @_;
    $_->walk_depth_first( sub {
        my ($node, $level) = @_;
        next if !$node->is_leaf || $self->enumval_in_use($node);

        $node->remove;
        $::db->delete(Enumval => $node->id);
        1;
    }) for $self->_tops;
}

# Merge a structure of nested HASHes which resembles a tree into the
# existing tree.  When a node in the 'other' tree has an id, it matches
# ids in the database.

sub _update_node($$)
{   my ($self, $node, $other) = @_;

    my $old_childs = index_by_id $node->children;
    my $new_childs = $other->{children} || [];
    my %new_names;   # child names to detect duplicates

  CHILD:
    foreach my $new_child (@$new_childs)
    {   my $text = $new_child->{text} =~ s/\s{2,}/ /gr =~ s/^\s+//r =~ s/\s+$//r;

        # Newly created elements have id like 'j1_12': invalid
        my $new_id = is_valid_id $new_child->{id};

        if(my $already = $new_names{$text})
        {   # Name already seen on this level: merge!
            $new_id or next CHILD;    # simplest case: attempt to add duplicate

            # Reassign enum datums to first enumval
            $::db->update(Enum => { layout_id => $new_id }, { layout_id => $already->id });
            $already->enumval->update({deleted => 0});
            next CHILD;  # stays in $old_childs for deletion
        }

        my $current;
        if($current = delete $old_childs->{$new_id // ''})
        {   # Child node reusable
            my $curval = $current->enumval;
            $curval->update({value => $text, deleted => 0})
                if $curval->value    ne $text
                || $curval->deleted;
        }
        else
        {   # New child node required
            error __x"Cannot add child node '{name}' below '{parent.name}' is in use and End Node Only set",
                name => $text, parent => $node
                if $node->is_leaf
                && $self->end_node_only
                && $self->enumval_in_use($node->id);

            my $parent_id = $node->name eq 'Root' ? undef : $node->id;
            my $r = $::db->create(Enumval => { layout_id => $self->id, parent => $parent_id,
                value => $text });

            my $enumval  = $::db->get_record(Enumval => $r->id);
            $current = Linkspace::Column::Tree::Node->new(enumval => $enumval);
        }

        $new_names{$text} = $current;
        $self->_update_node($current, $new_child);
    }

    # All remaining old childs set to deleted, at the end of the order
    # Children of missing children are deleted as well.

    $_->walk(sub { $_[0]->enumval->update({deleted => 1}) })
        for values %$old_childs;
}

sub _update_tree($%)
{   my ($self, $other, %args) = @_;
    $other = { children => $other } if ref $other eq 'ARRAY';
    $self->_update_node($self->tree, $other);

    # Bluntly rebuild all: no peephole minor changes to the tree
    $self->_enumvals($self->_build_enumvals);
    $self->tree($self->_build_tree);
    $self;
}

# Merge a foreign tree into the existing one: it will not cause deletions and
# avoid duplicated names.  A map will be created from ids found in imported tree
# to ids in the current database.

# We do not want to duplicate the node handling (and testing) of update_tree,
# so translate the import into an updated tree as could have arrived from
# the webpage.

sub _merge_children($$)
{   my ($self, $parent, $other) = @_;
    my $has = $parent->{children} ||= [];
    my %has = map $_->{name}, @$has;

    foreach my $add (@{$other->{children} || []})
    {   if(my $p = $has{$add->{name}})
        {   $self->_merge_children($p, $add);
        }
        else
        {   push @$has, $add;
        }
    }
}

sub _collect_map($$$)
{   my ($self, $node, $other, $map) = @_;
    foreach my $add (@{$other->{children} || []})
    {   my $child = first { $_->name eq $add->{name} } $node->children;
        $child or panic $add->{name};
        $map->{$add->{id}} = $child->{id};
        $self->_collect_map($child, $add, $map);
    }
}

sub _import_tree
{   my ($self, $other, $map, %args) = @_;

    my $have = $self->to_hash(include_deleted => 1);
    $self->_merge_children($have, $other);
    $self->_update_tree($have);
    $self->_collect_map($self->tree, $other, $map);
    $self;
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

#======================
# A simple, dedicated, tree implementation.

package Linkspace::Column::Tree::Node;

use Log::Report  'linkspace';
use Scalar::Util qw(weaken);
use List::Util   qw(first);

sub new(%)
{   my ($class, %node) = @_;
    my $childs  = delete $node{children} || [];
    my $parent  = delete $node{parent};
    $node{_kids} = [];
    $node{name} ||= $node{enumval}->value;
    my $self = bless \%node, $class;
    $self->add_child($_) for @$childs;
    $parent->add_child($self) if $parent;
    $self;
}

sub id         { $_[0]->enumval->id }
sub name       { $_[0]->{name} }
sub is_deleted { $_[0]->enumval->deleted }
sub enumval    { $_[0]->{enumval} }

sub add_child($)
{   my ($self, $child) = @_;
    push @{$self->{_kids}}, $child;
    $child->set_parent($self);
    $child;
}

sub set_parent($)
{   my ($self, $parent) = @_;
    $self->{_parent} = $parent;
    weaken($self->{_parent}) if $parent;
    $parent;
}

sub children() { @{$_[0]->{_kids}} }
sub parent()   { $_[0]->{_parent} }
sub is_root()  { ! $_[0]->{_parent} }
sub is_top()   { my $p = $_[0]->{_parent}; $p && $p->is_root }
sub is_leaf()  { ! @{$_[0]->{_kids}} }

sub remove()
{   my $self = shift;
    my $parent = $self->parent or return;
    $parent->{_kids} = [ grep $_->id != $self->id, $parent->children ];
}

sub walk($$)
{   my ($self, $cb, $level) = @_;
    $level //= 1;
    $cb->($self, $level), (map $_->walk($cb, $level+1), $self->children);
}

sub walk_depth_first($$)
{   my ($self, $cb, $level) = @_;
    $level //= 1;
    (map $_->walk_depth_first($cb, $level+1), $self->children), $cb->($self, $level);
}

# Return all nodes which do not have childs.
sub leafs { [ grep $_->is_leaf, @{$_[0]->nodes} ] }

# Find an element by name
sub find(@)
{   my $self  = shift;
    return $self if ! @_;
    my $next  = shift;
    my $found = first { $_->name eq $next } $self->children;
    $found && @_ ? $found->find(@_) : $found;
}

sub path()
{   my $self = shift;
    return '' if $self->is_root;
    $self->parent->path . $self->name . ($self->is_leaf ? '' : '/');
}

1;
