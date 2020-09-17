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

###
### META
###

__PACKAGE__->register_type;

sub db_field_extra_export { [ 'end_node_only' ] }
sub form_extras     { [ 'end_node_only' ], [] }
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

    if(my $other = delete $extra->{tree})
    {   $self->_update_tree($self->tree, $other, %args);
    }

    $self->delete_unused_enumvals unless $args{keep_deleted};
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

=head2 my $tree = $column->tree;
The selection tree as structured nodes, which are C<::Column::Tree::Node> instances
(implemented in the same source file)  The root element on top is used to group
the possible existence of multiple trees.
=cut

has tree => (is => 'rw', lazy => 1, builder => '_build_tree');

sub _build_tree
{   my $self  = shift;
    my $enumvals = $self->enumvals(include_deleted => 1, order => 'position');
    my @nodes = map Linkspace::Column::Tree::Node->new(enumval => $_), @$enumvals;
    my $nodes = index_by_id @nodes;

    my ($tops, $leafs) = part { $_->parent ? 1 : 0 } @nodes;
    $nodes->{$_->parent}->add_child($_) for @$leafs;

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
    $self->tree->walk(sub { $_[0]->id==$node_id or return 1; $result = $_[0]; 0 });
    $result;
}

=head2 \@nodes = $column->nodes;
Returns all non-deleted nodes for the tree.
=cut

sub nodes
{   my @nodes;
    $_[0]->tree->walk( sub { push @nodes, $_[0] unless $_[0]->is_deleted; 1 } );
    \@nodes;
}

=head2 \@leafs = $column->leafs;
Return all nodes which do not have childs.
=cut

sub leafs { [ grep $_->is_leaf, @{$_[0]->nodes} ] }

=head2 \%h = $column->to_hash(\@selected_ids);
Returns the structure the tree as nested HASHes.  Selections are
based on enumval ids.
=cut

sub to_hash
{   my ($self, $selected_ids) = @_;

    #XXX Used??
    my %is_selected = map +($_ => 1), @{$selected_ids || []};

    # Children are passed one level up via this array of "returned per level"
    # hashes.  So, $level_childs[3] contains the children to of the currently
    # being constructed parent on level 3.
    my @level_childs;

    $self->tree->walk_depth_first(sub
      { my ($node, $level) = @_;
        my $enumval = $node->enumval;
        my $childs  = $level_childs[$level] || [];

        push @{$level_childs[$level-1]}, +{
            id       => $enumval->id,
            text     => $enumval->value, 
            children => $childs,
            state    => ($is_selected{$enumval->id} ? { selected => \1 } : undef),
        } if @$childs || ! $enumval->deleted;

        undef $level_childs[$level];   # reset for sibling node
        1;
      });

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

sub resultset_for_values
{   my $self = shift;
    $self->end_node_only ? $self->leafs : $self->nodes;
}

=head2 $column->_update_tree($tree, $other, %options);
Merge a structure of nested HASHes which resembles a tree into the
existing tree.  When a node in the 'other' tree has an id, it matches
ids in the database.
=cut

### 2020-09-17: columns in GADS::Schema::Result::Enumval
# id         value      deleted    layout_id  parent     position

sub _update_tree($$%)
{   my ($self, $parent, $other, %args) = @_;

    my $old_childs = index_by_id $parent->children;
    my $new_childs = $other->{children} || [];
    my $position   = 0;

    foreach my $new_child (@$new_childs)
    {   my $text = $new_child->{text} =~ s/\s{2,}/ /gr =~ s/^\s+//r =~ s/\s+$//r;
        $position++;

        # Newly created elements have id like 'j1_12': invalid
        my $new_id = is_valid_id $new_child->{id};

        if(my $current = delete $old_childs->{$new_id // ''})
        {   # Node reusable
            my $curval = $current->enumval;
            $curval->update({value => $text, position => $position, deleted => 0})
                if $curval->value ne $text
                || $curval->position != $position
                || $curval->deleted;
        }
        else
        {   # New node
            my $r = $::db->create(Enumval => { value => $text, position => $position });
            my $enumval = $::db->get_record(Enumval => $r->id);
        }
    }

    # All remaining old childs set to deleted, at the end of the order
    # Children of missing children are deleted as well.

    $_->walk(sub { $_[0]->enumval->update({deleted => 1}) })
        for values %$old_childs;

    # Bluntly rebuild all: no peephole minor changes to the tree

    $self->_enumvals($self->_build_enumvals);
    $self->_tree($self->_build_tree);
}

=pod

        }
    }

    my $tid       = 
    my $rec       = $tid ? $enumvals->{$tid} : undef;
    my $name      = $t->{text};

    if($rec)
    {   if($rec->value ne $t->{text})
        {   info __x"column {col.path} rename tree enum '{from}' to '{to}'",
                col => $self, from => $rec->value, to => $name;
            $rec->value($name);
        }

        if($rec->deleted)
        {   info __x"column {col.path} deleted tree enum '{name}' revived",
                col => $self, name => $name;
            $rec->deleted(0);
        }

        $::db->update(Enumval => $tid, { value  => $t->{text}, deleted => 0 });
        $enum_mapping->{$source_id} = $tid;
    }
    else
    {   # new entry
        $tid = $::db->create(Enumval => {
            layout_id => $self->id,
            parent    => $parent_id,
            value     => $name,
        })->id;
        info __x"column {col.path} add tree enum '{name}'",
            col => $self, name => $name;

        $rec = $enumvals->{$tid} = $::db->get_record(Enumval => $tid);
        $enum_mapping->{$source_id} = $tid;
    }

    $self->_update($_, $tid, $enum_mapping)
         for @{$t->{children}};
}

=head2 $column->_import_tree($other, \%enum_mapping, %options);
Import tree information from an external source.  C<enum_mapping> will
be filled with the externally used ids mapped to the current ids in the
database.
#=cut

sub _import_branch
{   my ($self, $old_in, $new_in, %options) = @_;
    my $report = $options{report_only};
    my @old = sort { $a->{text} cmp $b->{text} } @$old_in;
    my @new = sort { $a->{text} cmp $b->{text} } @$new_in;
    my @to_write;

    while (@old)
    {   my $old = shift @old;
        my $new = shift @new;

        # If it's the same, easy, onto the next one
        if ($old->{text} && $new->{text} && $old->{text} eq $new->{text})
        {   trace __x"No change for tree value {value}", value => $old->{text};
            $new->{source_id} = $new->{id};
            $new->{id} = $old->{id};
            push @to_write, $new;
        }
        # This one is different. Is the next one the same?
        elsif($old[0] && $new[0] && $old[0]->{text} eq $new[0]->{text})
        {   # Yes, assume the previous is a value change
            info __x"Changing tree value {old} to {new}", old => $old->{text}, new => $new->{text};
            $new->{source_id} = $new->{id};
            $new->{id} = $old->{id};
            push @to_write, $new;
        }
        # Is the next new one the same as the current old one?
        elsif($new[0] && $old->{text} eq $new[0]->{text})
        {  # Yes, assume insert new value
            info __x"Adding tree value {new}", new => $new->{text};
            $new->{source_id} = delete $new->{id};
            push @to_write, $new;
            unshift @old, $old;     # old one back onto stack for processing next loop
        }
        elsif($options{force})
        {   if($new->{text})
            {   notice __x"Unknown treeval update {value}, forcing as requested", value => $new->{text};
                $new->{source_id} = delete $new->{id};
                push @to_write, $new;
            }
            else
            {   notice __x"Treeval {value} appears to no longer exist, force removing as requested", value => $old->{text};
            }
        }
        else
        {   # Different, don't know what to do, require manual intervention
            error __x"don't know how to handle tree updates for {column.name}, manual "
              . "intervention required (failed at old {old} new {new})",
                column => $self->name, old => $old->{text}, new => $new->{text};
        }

        my $kids = $new->{children} || [];
        $new->{children} = [ $self->_import_branch($old->{children}, $kids, %options) ]
            if @$kids;
    }

    # Add any remaining new ones
    delete $_->{id} for @new;
    (@to_write, @new);
}

=cut

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
use Scalar::Util qw(weaken);
use Log::Report  'linkspace';

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

sub id      { $_[0]->enumval->id }
sub name    { $_[0]->{name} }
sub enumval { $_[0]->{enumval} }

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
sub is_top()   { my $p = $_[0]->{_parent}; $p && $_[0]->is_root($p) }
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

1;
