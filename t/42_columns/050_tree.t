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

my $leaf_node = $column1->tree->find('b', 'b1')->id;
is $column1->is_valid_value($leaf_node), $leaf_node,  'leaf node where end_node_only';

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

# Still to test: duplicate names

ok $column1->end_node_only, 'flag end_node_only set';

my $column1b = Linkspace::Column->from_id($column1->id);
is_deeply $column1->to_hash, $column1b->to_hash, 'check tree was saved';

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

my $top_node = $column2->tree->find('abc');
is $column2->is_valid_value($top_node->id), $top_node->id, 'valid top node';
my $intermediate_node = $column2->tree->find('abc', 'abc1');
is $intermediate_node->path, 'abc/abc1/', 'intermediate node path';
is $column2->is_valid_value($intermediate_node->id), $intermediate_node->id, 'valid intermediate';

is_deeply $column2->values_beginning_with('a'), ['aa', 'ab/', 'abc/'], '... find top nodes';
is_deeply $column2->values_beginning_with('aa'), ['aa'], '... full match';
is_deeply $column2->values_beginning_with('aa/'), [ ], '... non-leaf node only';
is_deeply $column2->values_beginning_with('ab/'), ['ab/ab1', 'ab/ab2'], '... all leaf nodes';
is_deeply $column2->values_beginning_with('ab/a'), ['ab/ab1', 'ab/ab2'], '... some leaf nodes';
is_deeply $column2->values_beginning_with('ab/c'), [ ], '... no match';
is_deeply $column2->values_beginning_with('e'), [ ], '... no match';
is_deeply $column2->values_beginning_with(''), ['aa','ab/','abc/'], '... all tops';


try { $column1->is_valid_value($valid_id) };
my $error_message1 = $@->wasFatal->message;
is $error_message1, "Node 'c12' has been deleted and can therefore not be used", 'for deleted node';

try {  $column1->is_valid_value(-1); } ;
my $error_message2 = $@->wasFatal->message;
is $error_message2, "Node '-1' is not a valid tree node for 'column1 (long)'", 'non-existing node';

my $intermediate_node3 = $column1->tree->find('b')->id;
try { $column1->is_valid_value($intermediate_node3) };
my $error_message3 = $@->wasFatal->message;
is $error_message3, "Node 'b' cannot be used: not a leaf node", 'error with parent where end_node_only';

###
### Merge tree
###
# New tree from external source (CSV import?) May contain different nodes which
# need to get merged in.  A map is built from the external ids to internal ids
# be able to import the tree datums.

my @tops4 = (    # for now, same as @tops1
   { text => 'a' },
   { text => 'b', children => [ { text => 'b1' }, { text => 'b2' } ] },
   { text => 'c', children => [ { text => 'c1', children => [ { text => 'c12' } ] }] },
);

my $column4 = $layout->column_create({
    type          => 'tree',
    name          => 'column4 (long)',
    name_short    => 'column4',
    tree          => \@tops4,
});
like logline, qr/created.*column4/, '... created column4';

ok $column4, "Start merging an external tree";

my @merge4 = (
   { text => 'a', id => 42,   # exists
        children => [ { text => 'a1', id => 43 } ] },  # add level of leafs
   { text => 'b', id => $column4->tree->find('a')->id, # add confusion
        children => [ { text => 'b2', id => 44 },      # use sibling
                      { text => 'b3', id => 45 } ] },  # add sibling
   { text => 'd', id => 46 },                          # new top
   { text => 'e', id => 47,                            # new top with child
        children => [ { text => 'e1', id => 48 } ] },
);

my %map4;
$layout->column_update($column4, { tree => \@merge4 }, import_tree => \%map4);
ok keys %map4, '... merge created a map';

my $hash4 = $column4->to_hash;
is $column4->as_string, <<'__EXPECT', '... as_string as expected';
tree             column4
       a
           a1
       b
           b1
           b2
           b3
       c
           c1
               c12
       d
       e
           e1
__EXPECT

my $tree4 = $column4->tree;
is_deeply \%map4, {
    $tree4->find('a')->id => $tree4->find('b')->id,   # do not be confused
    42 => $tree4->find('a')->id,
    43 => $tree4->find('a', 'a1')->id,
    44 => $tree4->find('b', 'b2')->id,
    45 => $tree4->find('b', 'b3')->id,
    46 => $tree4->find('d')->id,
    47 => $tree4->find('e')->id,
    48 => $tree4->find('e', 'e1')->id,
}, '... check map';


### reuse nodes

my @tops5a = (
   { text => 'aa' },
   { text => 'ab', children => [ { text => 'ab1' }, { text => 'ab2' } ] },
   { text => 'abc', children => [ { text => 'abc1', children => [ { text => 'abc12' } ] }] },
);

my $column5 = $layout->column_create({
    type          => 'tree',
    name          => 'column5 (long)',
    name_short    => 'column5',
    tree          => \@tops5a,
});
like logline, qr/created.*column5/, '... created column5';
 
my @tops5b = (
    { text => 'aa' },
    { text => 'ab', children => [ { text => 'ab2' } ] },   # deleted: { text => 'ab1' }
    { text => 'abc', children => [ { text => 'abc1' }] },  # deleted: children => [ { text => 'abc12' } ]
    );

my @result_value5a = map +{ id => $_->id, value => $_->value,
    deleted => $_->deleted, parent => $_->parent ? $_->parent->id: undef }, 
    @{$column2->enumvals(include_deleted => 1, order => 'asc')};

$layout->column_update($column5, { tree => \@tops5b },keep_unused => 1);

my @result_value5b = map +{ id => $_->id, value => $_->value,
    deleted => $_->deleted, parent => $_->parent ? $_->parent->id: undef }, 
    @{$column5->enumvals(include_deleted => 1, order => 'asc')};

is $column5->as_string, <<'__STRING', '... reuse node';
tree             column5
       aa
       ab
    D      ab1
           ab2
       abc
           abc1
    D          abc12
__STRING


### Check to_hash(include_deleted)

my @tops6a = (
   { text => 'aa' },
   { text => 'ab', children => [ { text => 'ab1' }, { text => 'ab2' } ] },
   { text => 'abc', children => [ { text => 'abc1', children => [ { text => 'abc12' } ] }] },
);

my $column6 = $layout->column_create({
    type          => 'tree',
    name          => 'column6 (long)',
    name_short    => 'column6',
    tree          => \@tops6a,
});
like logline, qr/created.*column6/, 'Check to_hash(include_deleted)';
my $tree6 = $column6->tree;
 
my @tops6b  =
( { text     => 'aa', id => $tree6->find('aa')->id,
  },
  { text     => 'ab', id => $tree6->find('ab')->id,
    children => [
        { text => 'ab2', id => $tree6->find('ab', 'ab2')->id,
          # deleted: { text => 'ab1' }
        },
    ],
  },
  { text     => 'abc', id => $tree6->find('abc')->id,
    children => [
        { text => 'abc1', id => $tree6->find('abc', 'abc1')->id,
          # deleted children => [ { text => 'abc12' } ]
        },
    ],
  }
);

$layout->column_update($column6, { tree => \@tops6b }, keep_unused => 1);
my $to_hash6  = Dumper($column6->to_hash(include_deleted => 0));
my $to_hash6a = Dumper($column6->to_hash(include_deleted => 0));
is $to_hash6, $to_hash6a, '... does check via Dumper work?';

my $to_hash6_include_deleted = Dumper($column6->to_hash(include_deleted => 1));
isnt $to_hash6, $to_hash6_include_deleted, '... effect include_deleted';

### Check delete_unused_enumvals()

$column6->delete_unused_enumvals;
is $column6->as_string, <<'__STRING', 'Unused enumvals removed';
tree             column6
__STRING

diag 'need to test keeping used enumvals';

done_testing;
