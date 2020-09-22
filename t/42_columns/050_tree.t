# Check the Integer column type

use Linkspace::Test;

$::session = test_session;
my $sheet = test_sheet;
my $layout = $sheet->layout;

my $column1 = $layout->column_create({
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

### empty tree

my $root = $column1->tree;
isa_ok $root, 'Linkspace::Column::Tree::Node', 'Start with empty tree';
ok $root->is_root, '... is root';
cmp_ok $root->children, '==', 0, '... no children';
is $root->name, 'Root', '... name';

is $column1->as_string, <<'__STRING', '... show empty tree';
tree             column1
__STRING

### Add some tops

# The web-interface produces a very cluttered nested HASH structure, with
# only 'id' as additional useful value (to detect renames)
my @tops1 = (
   { text => 'a' },
   { text => 'b', children => [ { text => 'b1' }, { text => 'b2' } ] },
   { text => 'c', children => [ { text => 'c1', children => [ { text => 'c12' } ] }] },
);

$layout->column_update($column1, { tree => \@tops1 });

my $root2 = $column1->tree;
isnt $root2, $root, 'Created tree';
cmp_ok $root2->children, '==', @tops1, '... three tops';

### Structural check

is $column1->as_string, <<'__STRING', '... show tree with 3 tops';
tree             column1
       a
       b
           b1
           b2
       c
           c1
               c12
__STRING

### Find (also tested in the 'note' script)

my $node_b = $column1->tree->find('b');
ok $node_b, '... find node b';
ok $node_b->is_top, '... is top';
ok ! $node_b->is_leaf, '... is not leaf';

my $node_b1 = $column1->tree->find('b', 'b1');
ok $node_b1, '... find node b1';
ok ! $node_b1->is_top, '... is not top';
ok   $node_b1->is_leaf, '... is leaf';

ok ! $column1->tree->find('b', 'error'), '... not found unknown';

### Get node

my $n1 = $column1->node($node_b1->id);
ok defined $n1, 'Find node by id';
is $n1, $node_b1, '... correct one';

ok ! defined $column1->node(-1), '... wrong id';

### Hash output for website

my $as_hash1 = $column1->to_hash(selected_ids => [ $node_b->id, $node_b1->id ]);
my $expect1  =
[ { text     => 'a', id => $column1->tree->find('a')->id,
  },
  { text     => 'b', id => $node_b->id,
    children => [
      { text     => 'b1', id => $node_b1->id,
        state    => { selected => \1 },
      },
      { text     => 'b2', id => $column1->tree->find('b', 'b2')->id,
      }
    ],
    state => { selected => \1 },
  },
  { text     => 'c', id => $column1->tree->find('c')->id,
    children => [
      { text => 'c1', id => $column1->tree->find('c', 'c1')->id,
        children => [
          { text => 'c12', id => $column1->tree->find('c', 'c1', 'c12')->id,
          }
        ],
      }
    ],
  }
];

is_deeply $as_hash1, $expect1, 'Output as hash';

### Hash update
# Base changes on the HASH of the current tree.

my $update = $column1->to_hash;
shift $update;   # remove top 'a'
push $update, { text => 'd', children => [ { text => 'd1' } ] };  # add top
unshift @{$update->[0]{children}}, { text => 'b0' };  # add in front
$update->[0]{children}[1]{text} = 'b1b';  # rename
delete $update->[0]{children}[2];   # remove single b2
delete $update->[1]{children}[0];   # remove tree c1/c12

$layout->column_update($column1, { tree => $update, end_node_only => 1 });
like logline, qr/changed field.*end_node_only/, 'New tree, end_node_only';

is $column1->as_string, <<'__STRING', 'Updated tree';
tree             column1
    D* a
       b
     *     b0
     *     b1b
    D*     b2
       c
    D      c1
    D*         c12
       d
     *     d1
__STRING

# Still to test: duplicate names

#TODO: _is_valid_value($node_id) existing node
#TODO: _is_valid_value($node_id) non-existing node
#TODO: _is_valid_value($node_id) for deleted node
#TODO: _is_valid_value($node_id) with leaf where end_node_only
#TODO: _is_valid_value($node_id) error with parent where end_node_only
#TODO: Linkspace::Column->from_id($column1->id)  check tree was saved

#TODO: $column->values_beginning_with (separate testscript typeahead?)

#### test column_update($c, { tree => \@t })    update
#### test column_update($c, { tree => \@t }, import_tree => \%map)  import
#TODO: delete first child: still in there but flagged 'deleted'
#TODO: $column1->to_hash(include_deleted => 0);
#TODO: $column1->to_hash(include_deleted => 1);
#TODO: delete_unused_enumvals()

done_testing;
