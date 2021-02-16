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
    $self->parent->path . $self->name . ($self->is_leaf ? '' : '#');
}

sub as_string() { join '#', map $_->name, $_[0]->ancestors, $_[0] }

sub ancestors()
{   my $parent = $_[0]->parent or return;
    $parent->is_root ? () : ($parent->ancestors, $parent);
}

1;
