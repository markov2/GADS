# Check the Intgr column type

use Linkspace::Test;

$::session = test_session;
my $sheet = empty_sheet;

my $column1 = $sheet->layout->column_create({
    type          => 'intgr',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_multivalue => 0,
    is_optional   => 0,
});
ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/intgr=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

is $column1->as_string, <<'__STRING', '... as string';
intgr            column1
__STRING

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Intgr', '...';

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
isa_ok $column1d, 'Linkspace::Column::Intgr', '...';

# is_valid_value

test_valid_values $column1, [
    [1, 'normal id',                 '18',     '18'                                            ],
    [0, 'invalid id',                'abc',    '\'abc\' is not a valid integer for \'column1 (long)\''],
    [1, 'negative number',           '-123',   '-123'                                          ],
    [1, 'postive number',            '+234',   '+234'                                          ],
    [0, 'empty string',              '',       '\'\' is not a valid integer for \'column1 (long)\''],
    [1, 'leading space',             ' 5',     '5'                                             ],
    [1, 'trailing space',            '6 ',     '6'                                             ],
    [1, 'multiple leading and trailing spaces', '  78  ', '78'                                            ],
    [0, 'number containing a space', '67 89',  '\'67 89\' is not a valid integer for \'column1 (long)\''],
];


#is_deeply $column1->export_hash, {},  "... undef in multi value";
#exclude undefs
#renamed

done_testing;
