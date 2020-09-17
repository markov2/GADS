# Test the node processing, run-time part of the tree management.

use Linkspace::Test;

$::session = test_session;
my $sheet = test_sheet;

{   #### simulate table Enumval result class
    package Enumval;

    sub new(%) { my $class = shift; bless { @_ }, $class }
    sub id { $_[0]->{_id} }
    sub value { $_[0]->{_value} }
}

### Check Enumval simulation

my $id = 1;
sub new_enum($) { Enumval->new(_id => $id++, _value => $_[0]) }

my $a = new_enum 'a';
ok defined $a, 'Check enumval creation';
isa_ok $a, 'Enumval', '... ';
cmp_ok $a->id, '==', 1, '... id';
is $a->value, 'a', '... value';

### Create a node

sub new_node(%)
{   my ($enumval, %args) = @_;
    Linkspace::Column::Tree::Node->new(enumval => $enumval, %args);
}

my $na = new_node $a, enumval => $a;
ok defined $na, 'Check node creation';
isa_ok $na, 'Linkspace::Column::Tree::Node', '... ';
is $na->name, 'a', '... name';
is_deeply [ $na->children ], [], '... no children';
ok ! defined $na->parent, '... no parent';
is $na->enumval, $a, '... enumval';

### Parent child

my $nb = new_node new_enum('b');
ok defined $nb, 'Create parent node';
is_deeply [ $nb->children ], [], '... no children yet';
is $nb->add_child($na), $na, '... add child';
is_deeply [ $nb->children ], [ $na ], '... first child';
ok defined $na->parent, '... child got parent';
is $na->parent, $nb, '... expected parent';
ok ! defined $nb->parent, '... parent did not get parent';

ok   $nb->is_top, '... parent is top';
ok ! $nb->is_leaf, '... parent is not leaf';
ok ! $na->is_top, '... child is not top';
ok   $na->is_leaf, '... child is leaf';

### Walk

my $nc = new_node new_enum('c');
ok defined $nb->add_child($nc), 'Added second child';

my $nd = new_node new_enum('d');
ok defined $nb->add_child($nd), 'Added third child';

is_deeply [ $nb->children ], [ $na, $nc, $nd ], '... all found';

my @path;
sub node_def { push @path, [ $_[0]->name, $_[1] ] }

@path = ();
$na->walk(\&node_def);
is_deeply \@path, [ [ a => 1 ] ], 'Walk straight, Leaf';

@path = ();
$nb->walk(\&node_def);   # top
is_deeply \@path, [ [ b => 1], [ a => 2 ], [ c => 2 ], [ d => 2 ] ],
    'Walk straight, Top';

@path = ();
$na->walk_depth_first(\&node_def);
is_deeply \@path, [ [ a => 1 ] ], 'Walk depth first, Leaf';

@path = ();
$nb->walk_depth_first(\&node_def);
is_deeply \@path, [ [ a => 2 ], [ c => 2 ], [ d => 2 ], [ b => 1] ],
    'Walk depth first, Top';

### Params at construction

my $new_top = new_node new_enum('t');
my $ne = new_node new_enum('e'), children => [ $na, $nc, $nd ], parent => $new_top;
ok defined $ne, 'Construct at instantiation';

@path = ();
$new_top->walk(\&node_def);
is_deeply \@path, [ [ t => 1 ], [ e => 2 ], [ a => 3 ], [ c => 3 ], [ d => 3 ]],
    '... check structure';

### Remove child

cmp_ok $ne->children, '==', 3, 'Remove a child of $ne';
is $na->parent, $ne, '... check relation';
$na->remove;
cmp_ok $ne->children, '==', 2, '... child of $ne removed';

$nb->remove;
cmp_ok $ne->children, '==', 2, '... not a child of $ne, not removed';

done_testing;
