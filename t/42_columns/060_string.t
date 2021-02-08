# Check the String column type

use Linkspace::Test;

$::session = test_session;
my $sheet = empty_sheet;

my $column1 = $sheet->layout->column_create({
    type          => 'string',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_textbox    => 0,
    force_regex   => '',
    is_multivalue => 0,
    is_optional   => 0,
});
ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/string=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

is $column1->as_string, <<'__STRING', '... as_string';
string           column1
__STRING

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::String', '...';

ok $column1->can_multivalue, '... can multivalue';

### by short_name from cache
my $column1b = $sheet->layout->column('column1');
ok defined $column1b, 'Reload via name';
is $column1b->id, $col1_id;

### by id from cache
my $column1c = $sheet->layout->column($col1_id);
ok defined $column1b, 'Reload via id';
is $column1b->id, $col1_id,'... loaded with id';

### low level instantiate to avoid the cache
my $column1d = Linkspace::Column->from_id($column1->id, sheet => $sheet);
isnt $column1d, $column1, 'recreated object';
ok defined $column1d, 'Reload via id, avoiding cache';
isa_ok $column1d, 'Linkspace::Column::String', '...';

#### is_valid_value simple

test_valid_values $column1, [
    [ 1, 'normal string', 'from here to there',          'from here to there'  ],
    [ 1, 'mapping of spaces', "start:\tx\xA0x\nx :end",  'start: x x x :end'   ],
    [ 1, 'multiple spaces to single space', 'multiple: 1, 2  ,3   ,etc',  'multiple: 1, 2 ,3 ,etc',  ],
    [ 1, 'removal of leading space', ' leading space',   'leading space'       ],
    [ 1, 'removal of trailing space', 'trailing space ', 'trailing space'      ],
    [ 1, 'a combination of the above', "\t\n\xA0 part1 \n\t\xA0 part2 \t\xA0\n  ", 'part1 part2' ],
];

#### is_valid_value boxed

my $column2 = $sheet->layout->column_create({
    type          => 'string',
    name          => 'column2 (long)',
    name_short    => 'column2',
    is_textbox    => 1,
    force_regex   => '',
    is_multivalue => 1,
    is_optional   => 1,
});
logline;

ok defined $column2, "Created column as textbox, no regex, multivalue, optional";

is $column2->as_string, <<'__STRING', '... as_string';
string       MO  column2
    is textbox
__STRING

test_valid_values $column2, [
    [ 1, 'empty line',            "\n",                            '' ,                         ],
    [ 1, 'empty lines',           "\n\n\n",                        '' ,                         ],
    [ 1, 'empty lines replaced',  "line1\n\n\nline2",              "line1\n\n\nline2\n" ,       ],
    [ 1, 'single line',           'single line',                   "single line\n" ,            ],
    [ 1, 'multiple lines',        "line1\nline2\nline3",           "line1\nline2\nline3\n" ,    ],
    [ 1, 'mapping of spaces',     "start: x\tx\xA0x\nx :end",      "start: x\tx x\nx :end\n"    ],
    [ 1, 'leading spaces intact', "   leading\n\ spaces\n lines",  "   leading\n spaces\n lines\n" ,  ],
    [ 1, 'trailing spaces removed', "trailing\n\ spaces\n lines   ", "trailing\n spaces\n lines\n",   ],
    [ 1, 'multiple spaces intact', "space1 space2  space0",         "space1 space2  space0\n"   ],
    [ 1, 'multiple spaces, lines intact', "sp1 sp2  sp0\nsp1 sp2  sp0",    "sp1 sp2  sp0\nsp1 sp2  sp0\n" , ],
    [ 1, 'leading lines removed',  "\n\nleading\n\ empty\n lines",  "leading\n empty\n lines\n" ],
    [ 1, 'trailing lines removed', "trailing\n\empty\nlines\n\n\n", "trailing\n\empty\nlines\n" ],
];

my $column3 = $sheet->layout->column_create({
    type          => 'string',
    name          => 'column3 (long)',
    name_short    => 'column3',
    is_textbox    => 1,
    force_regex   => '[0-9a-m\s:]*',
    is_multivalue => 1,
    is_optional   => 1,
});
logline;

ok defined $column3, "Created column as textbox, regex, multivalue, optional";

is $column3->as_string, <<'__STRING', '... as_string';
string       MO  column3
    is textbox, match: [0-9a-m\s:]*
__STRING

is $column3->is_valid_value('abc 0123'), "abc 0123\n" , '... match regex';
try { $column3->is_valid_value('invalid pattern') };
is $@->wasFatal->message, "Invalid value 'invalid pattern\n' for required pattern of column3 (long)",
    '... match regex failed';

is $column3->is_valid_value("  abc: d\te\xA0f\ng :hij\n\nklm\n\n"), "  abc: d\te f\ng :hij\n\nklm\n",
    '... combination of previous';

done_testing;
