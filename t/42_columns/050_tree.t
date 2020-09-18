# Check the Integer column type

use Linkspace::Test;

$::session = test_session;
my $sheet = test_sheet;

my $column1 = $sheet->layout->column_create({
    type          => 'tree',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_multivalue => 0,
    is_optional   => 0,
                                            });

ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/tree=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Enum', '...';
isa_ok $column1, 'Linkspace::Column::Tree', '...';

is $column1->as_string, <<'__STRING', '... show empty tree';
tree             column1
__STRING

# The web-interface produces a very cluttered nested HASH structure, with
# only 'id' as additional useful value (to detect renames)
my @tops1 = (
   { text => 'a' },
   { text => 'b', children => [ { text => 'b1' }, { text => 'b2' } ] },
   { text => 'c', children => [ { text => 'c1', children => [ { text => 'c12' } ] }] },
);

###
$sheet->layout->column_update($column1, { tree => \@tops1 });

is $column1->as_string, <<'__STRING', '... show tree with 3 tops';
tree             column1
__STRING

#TODO: empty tree() must return Node without children, named Root
#TODO: add top to empty tree, is_top(), ! is_leaf()
#TODO: nodes() report top
#TODO: $top->add_child($child).  Child is leaf, not top.  Top is not leaf
#TODO: ->node($id) and ->node($name)
#TODO: add second child to top
#TODO: check return of ->nodes() and leafs()
#TODO: $column->values_beginning_with
#TODO: delete first child: still in there but flagged 'deleted'
#TODO: delete_unused_enumvals()  Reload tree (by reloading column from_id) from
#       DB must not show it anymore
#TODO: _is_valid_value($node_id) existing node
#TODO: _is_valid_value($node_id) non-existing node
#TODO: _is_valid_value($node_id) for deleted node
#TODO: _is_valid_value($node_id) with leaf where end_node_only
#TODO: _is_valid_value($node_id) error with parent where end_node_only
#TODO: to_hash()

done_testing;
