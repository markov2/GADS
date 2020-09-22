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

my $valid_id = $column1->tree->find('c', 'c1', 'c12')->id;
is $column1->is_valid_value($valid_id), $valid_id, 'existing node';

my $top_leaf_node = $column1->tree->find('a')->id;
is $column1->is_valid_value($top_leaf_node), $top_leaf_node,  'top leaf node where end_node_only';

### Hash update
# Base changes on the HASH of the current tree.

my $update = $column1->to_hash;
shift @$update;   # remove top 'a'
push @$update, { text => 'd', children => [ { text => 'd1' } ] };  # add top
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

ok $column1->end_node_only, 'flag end_node_only';

my $column1b = Linkspace::Column->from_id($column1->id);
is_deeply $column1->to_hash, $column1b->to_hash, 'reload from database is identical';

###############################

my @tops2 = (
   { text => 'aa' },
   { text => 'ab', children => [ { text => 'ab1' }, { text => 'ab2' } ] },
   { text => 'abc', children => [ { text => 'abc1', children => [ { text => 'abc12' } ] }] },
);

my $column2 = $layout->column_create({
    type          => 'tree',
    name          => 'column2 (long)',
    name_short    => 'column2',
    is_multivalue => 0,
    is_optional   => 0,
    end_node_only => 0,
    tree          => \@tops2,
});
ok logline, "Created column2";

my $top_intermediate_node = $column2->tree->find('abc')->id;
is $column2->is_valid_value($top_intermediate_node), $top_intermediate_node, 'top intermediate';

is_deeply $column2->values_beginning_with('a'), ['aa', 'ab/', 'abc/'], '... find top nodes';
is_deeply $column2->values_beginning_with('aa'), ['aa'], '... full match';
is_deeply $column2->values_beginning_with('aa/'), [ ], '... non-leaf node only';
is_deeply $column2->values_beginning_with('ab/'), ['ab/ab1', 'ab/ab2'], '... find leaf nodes';
is_deeply $column2->values_beginning_with('ab/a'), ['ab/ab1', 'ab/ab2'], '... find leaf nodes';
is_deeply $column2->values_beginning_with('ab/c'), [ ], '... no match';
is_deeply $column2->values_beginning_with('e'), [ ], '... no match';
is_deeply $column2->values_beginning_with(''), ['aa','ab/','abc/'], '... all tops';

my @tops3 = (
   { text => 'daa' },
   { text => 'dab', children => [ { text => 'ab1' }, { text => 'ab2' } ] },
   { text => 'dabc', children => [ { text => 'abc1', children => [ { text => 'abc12' } ] }] },
);

my @result_value3 = map +{ id => $_->id, value => $_->value,
    deleted => $_->deleted, parent => $_->parent ? $_->parent->id: undef }, 
    @{$column2->enumvals(include_deleted => 1, order => 'asc')};

#print Dumper(@result_value3);

###############################


try { $column1->is_valid_value($valid_id) };
my $error_message1 = $@->wasFatal->message;
is $error_message1, "Node 'c12' has been deleted and can therefore not be used", 'for deleted node';

try {  $column1->is_valid_value(-1); } ;
my $error_message2 = $@->wasFatal->message;
is $error_message2, "Node '-1' is not a valid tree node for 'column1 (long)'", 'non-existing node';

my $intermediate_node = $column1->tree->find('b')->id;
try { $column1->is_valid_value($intermediate_node); } ;
my $error_message3 = $@->wasFatal->message;
is $error_message3, "Node 'b' cannot be used: not a leaf node", 'error with parent where end_node_only';

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
