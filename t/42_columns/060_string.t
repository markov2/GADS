# Check the String column type

use Linkspace::Test;

$::session = test_session;
my $sheet = test_sheet;

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

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::String', '...';

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

# is_valid_value

#
# line
#

is $column1->is_valid_value('from here to there'),                       'from here to there' ,    '... normal string';
is $column1->is_valid_value("start:\tx\xA0x\nx :end"),                   'start: x x x :end',      '... mapping of spaces';
is $column1->is_valid_value('multiple: 1, 2  ,3   ,etc'),                'multiple: 1, 2 ,3 ,etc', '... multiple spaces to single space';
is $column1->is_valid_value(' leading space'),                           'leading space',          '... removal of leading space';
is $column1->is_valid_value('trailing space '),                          'trailing space',         '... removal of trailing space';
is $column1->is_valid_value("\t\n\xA0 part1 \n\t\xA0 part2 \t\xA0\n  "), 'part1 part2',            '... a combination of the above';

#
# box, multivalue and optional
#

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

is $column2->is_valid_value("\n"),                            '' ,                            '... empty line';
is $column2->is_valid_value("\n\n\n"),                        '' ,                            '... empty lines';
is $column2->is_valid_value("line1\n\n\nline2"),              "line1\nline2" ,                '... empty lines replaced';
is $column2->is_valid_value('single line'),                   'single line' ,                 '... single line';
is $column2->is_valid_value("line1\nline2\nline3"),           "line1\nline2\nline3" ,         '... multiple lines';
is $column2->is_valid_value("start: x\tx\xA0x\nx :end"),      "start: x\tx x\nx :end",        '... mapping of spaces';
is $column2->is_valid_value("   leading\n\ spaces\n lines"),  "   leading\n spaces\n lines" , '... leading spaces intact';
is $column2->is_valid_value("trailing\n\ spaces\n lines   "), "trailing\n spaces\n lines",    '... trailing spaces removed';
is $column2->is_valid_value("space1 space2  space0"),         "space1 space2  space0" ,       '... multiple spaces intact';
is $column2->is_valid_value("sp1 sp2  sp0\nsp1 sp2  sp0"),    "sp1 sp2  sp0\nsp1 sp2  sp0" ,  '... multiple spaces, lines intact';
is $column2->is_valid_value("\n\nleading\n\ empty\n lines"),  "leading\n empty\n lines" ,     '... leading lines removed';
is $column2->is_valid_value("trailing\n\empty\nlines\n\n\n"), "trailing\n\empty\nlines" ,     '... trailing lines removed';
is_deeply $column2->is_valid_value(undef),                    [],                             '... undef optional';
is_deeply $column2->is_valid_value([]),                       [],                             '... array optional';
is_deeply $column2->is_valid_value(["line1\n\n\nline2",""]),  ["line1\nline2",""],            '... multivaltue';

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

is $column3->is_valid_value("abc 0123"),                      "abc 0123" ,                    '... match regex';
try { $column3->is_valid_value('invalid pattern'); };
is $@->wasFatal->message, "Invalid value 'invalid pattern' for required pattern of column3 (long)", '... match regex failed';
is $column3->is_valid_value("  abc: d\te\xA0f\ng :hij\n\nklm\n\n"), "  abc: d\te f\ng :hij\nklm",   '... combination of previous';

done_testing;
