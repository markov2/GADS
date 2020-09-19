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

#TODO: empty tree() must return Node without children, named Root

# The web-interface produces a very cluttered nested HASH structure, with
# only 'id' as additional useful value (to detect renames)
my @tops1 = (
   { text => 'a' },
   { text => 'b', children => [ { text => 'b1' }, { text => 'b2' } ] },
   { text => 'c', children => [ { text => 'c1', children => [ { text => 'c12' } ] }] },
);

###
TODO: $layout->column_update($column1, { tree => \@tops1 });
is $column1->as_string, <<'__STRING', '... show tree with 3 tops';
tree             column1
__STRING

#TODO: $column1->to_hash(selected_ids => \@ids)
#TODO: _is_valid_value($node_id) existing node
#TODO: _is_valid_value($node_id) non-existing node
#TODO: _is_valid_value($node_id) for deleted node
#TODO: _is_valid_value($node_id) with leaf where end_node_only
#TODO: _is_valid_value($node_id) error with parent where end_node_only
#TODO: Linkspace::Column->from_id($column1->id)  check tree was saved

#TODO: add top to empty tree, is_top(), ! is_leaf()
#TODO: $top->add_child($child).
#TODO: ->node($id)
#TODO: $node->path  b/b1
#TODO: ->find('b')     is top
#TODO: ->find('b/b1')
#TODO: ->find('b/c')   does not exist
#TODO: $column->values_beginning_with (separate testscript typeahead?)

#### test column_update($c, { tree => \@t })    update
#### test column_update($c, { tree => \@t }, import_tree => \%map)  import
#TODO: delete first child: still in there but flagged 'deleted'
#TODO: $column1->to_hash(include_deleted => 0);
#TODO: $column1->to_hash(include_deleted => 1);
#TODO: delete_unused_enumvals()
#TODO: to_hash()

done_testing;
