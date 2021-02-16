## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Tree;
use Log::Report 'linkspace';

use List::Util      qw(first);
use List::MoreUtils qw(part);

use Linkspace::Util qw(index_by_id is_valid_id);
use Linkspace::Column::Tree::Node  ();

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Column::Enum';

#XXX Enumval is not cleanly wrapped as Linkspace::DB::Table, but has a serious
#    problem with column 'parent' (which should have been named 'parent_id') and
#    the relation 'parent' which it defined.  Hence $ev->parent returns an object,
#    not the id.  Fix this dirty:
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
sub datum_class     { 'Linkspace::Datum::Tree' }
sub form_extras     { [ qw/end_node_only tree/ ], [] }
sub retrieve_fields { [ qw/id value/ ] }
sub sprefix         { 'value' }
sub suffix          { '(\.level[0-9]+)?' }
sub tjoin           { +{ $_[0]->field => 'value' } }
sub value_field_as_index { 'id' }
sub value_table     { 'Enum' }

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

sub is_valid_value($)
{   my ($self, $value) = @_;

    my $node = $self->node($value)
        or error __x"Node '{value}' is not a valid tree node for '{col.name}'",
            value => $value, col => $self;

    ! $node->is_deleted
        or error __x"Node '{node.name}' has been deleted and can therefore not be used",
            node => $node;

    ! $self->end_node_only || $node->is_leaf
        or error __x"Node '{node.name}' cannot be used: not a leaf node", node => $node;

    $node->id;
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
    my @path    = split m!\s*\#\s*!, $start, -1;
    my $partial = @path ? pop @path : '';

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
    my @nodes = map Linkspace::Column::Tree::Node->new(enumval => $_), @$enumvals;
    my $nodes = index_by_id \@nodes;

    my ($tops, $leafs) = part { $_->enumval->parent_id ? 1 : 0 } @nodes;
    $nodes->{$_->enumval->parent_id}->add_child($_)
        for sort { $a->name cmp $b->name } @{$leafs || []};

    Linkspace::Column::Tree::Node->new(name => 'Root', children => $tops);
}

sub _tops() { $_[0]->tree->children }

=head2 my $node = $column->node($node_id);
Returns a single node from the tree: returns a ::Node object.  Use C<$node->enumval>
to get to its database record.  Node names are only unique per parent, so names cannot
be used globally.
=cut

has _id2node => ( is => 'lazy', builder => sub {
    my %index;
    $_->walk(sub { $index{$_[0]->enumval->id} = $_[0]; 1 } )
        for $_[0]->_tops;
    \%index;
});

sub node($) { $_[0]->_id2node->{$_[1]} }

=head2 my $node = $column->node_by_name($name);
Returns the Node which contains the name.
=cut

# Names are unique, otherwise DisplayFilter has an issue
has _name2node => ( is => 'lazy', builder => sub {
    my %index;
    $_->walk(sub { $index{$_[0]->enumval->value} = $_[0]; 1 } )
        for $_[0]->_tops;
    \%index;
});

sub node_by_name($) { $_[0]->_name2node->{$_[1]} }

=head2 \%h = $column->to_hash(%options);
Returns the structure the tree as nested HASHes.
=cut

#XXX this is an ARRAY of the tops.  Do we need the root element.
sub to_hash
{   my ($self, %args) = @_;

    my $selected_ids = $args{selected_ids} || [];
    my %is_selected  = map +($_ => 1), @$selected_ids;

    my $include_deleted = $args{include_deleted};

    # Children are passed one level up via this array of "returned per level"
    # hashes.  So, $level_childs[3] contains the children to of the currently
    # being constructed parent on level 3.
    my @level_childs;

    $_->walk_depth_first(sub
      { my ($node, $level) = @_;
        my $enumval = $node->enumval;
        my $childs  = delete $level_childs[$level] || [];

        $include_deleted || ! $enumval->deleted || @$childs
            or return 1;

        my %def = (
            id       => $enumval->id,
            text     => $enumval->value, 
        );
        $def{children} = $childs if @$childs;
        $def{state}    = { selected => \1 } if $is_selected{$enumval->id};
        push @{$level_childs[$level-1]}, \%def;
        1;
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

sub _update_node($$%)
{   my ($self, $node, $other, %args) = @_;

    my $old_childs = index_by_id $node->children;    # node objects id/name
    my %old_names  = map +($_->name => $_), values %$old_childs;

    my $new_childs = $other->{children} || [];       # node hashes  id/text
    my %new_names;   # child names to detect duplicates

    # Normalize all new names
    s/\s{2,}/ /g,s/^\s//,s/\s$// for map $_->{text}, @$new_childs;

    # Merge branches of new childs with duplicate name into existing
    foreach my $new_child (grep ! $_->{id}, @$new_childs)
    {   my $old_node = $old_names{$new_child->{text}} or next;

        # Be careful that the existing node may have been renamed: search text, not id
        if(my $existing = first { $_->{id} && $_->{text} eq $new_child->{text}} @$new_childs)
        {   # Old node still exists
            push @{$existing->{children}}, @{$new_child->{children} || []};
            delete $new_child->{text};   # flag already processed
        }
        else
        {   # Old node is not mentioned anymore, steal it's id
            $new_child->{id} = $old_node->id;
        }
    }

  CHILD:
    foreach my $new_child (@$new_childs)
    {   my $text = $new_child->{text} // next;

        # Newly created elements have id like 'j1_12': invalid
        my $new_id = is_valid_id $new_child->{id};

        if(my $already = $new_names{$text})
        {   # Name already seen on this level: merge!
            $new_id or next CHILD;    # simplest case: attempt to add duplicate ignored

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
        $self->_update_node($current, $new_child, %args);
    }

    if($args{delete_missing})
    {   # All remaining old childs set to deleted, at the end of the order
        # Children of missing children are deleted as well.

        $_->walk(sub { $_[0]->enumval->update({deleted => 1}) })
            for values %$old_childs;
    }
}

sub _update_tree($%)
{   my ($self, $other, %args) = @_;
    $other = { children => $other } if ref $other eq 'ARRAY';

    my $missing = exists $args{delete_missing} ? $args{delete_missing} : 1;
    $self->_update_node($self->tree, $other, delete_missing => $missing);

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
    my %has = map +($_->{text} => $_), @$has;

    foreach my $add (@{$other->{children} || []})
    {   if(my $p = $has{$add->{text}})
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
    {   my $child = first { $_->name eq $add->{text} } $node->children;
        $child or panic $add->{text};
        $map->{$add->{id}} = $child->id;
        $self->_collect_map($child, $add, $map);
    }
}

sub _import_tree
{   my ($self, $other, $map, %args) = @_;
    $other = { children => $other } if ref $other eq 'ARRAY';

    my $have = { children => $self->to_hash(include_deleted => 1) };
    $self->_merge_children($have, $other);
    $self->_update_tree($have, delete_missing => 0);
    $self->_collect_map($self->tree, $other, $map);
    $self;
}

sub export_hash
{   my $self = shift;
    my $h = $self->SUPER::export_hash(@_);
    $h->{tree} = $self->to_hash;
    $h;
}

sub datum_as_string($) { $_[0]->node($_[1]->value)->name }

1;
