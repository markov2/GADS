# Check the Createddate column type

use Linkspace::Test;

my $sheet  = empty_sheet;
my $layout = $sheet->layout;

my $column1 = $layout->column_create({
    type          => 'createddate',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_multivalue => 0,
    is_optional   => 0,
});
ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/createddate=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Createddate', '...';

### by short_name from cache
my $column1b = $layout->column('column1');
ok defined $column1b, 'Reload via name';
is $column1b->id, $col1_id;

### by id from cache
my $column1c = $layout->column($col1_id);
ok defined $column1b, 'Reload via id';
is $column1b->id, $col1_id,'... loaded with id';

### low level instantiate to avoid the cache
my $column1d = Linkspace::Column->from_id($column1->id, sheet => $sheet);
isnt $column1d, $column1, 'recreated object';
ok defined $column1d, 'Reload via id, avoiding cache';
isa_ok $column1d, 'Linkspace::Column::Createddate', '...';

#### is_valid_value
my $column2 = $layout->column_create({
    type          => 'createddate',
    name          => 'column2 (long)',
    name_short    => 'column2',
    is_multivalue => 0,
});
logline;

test_valid_values $column2, [
    [1, 'simple date',     '2020-09-29',          '2020-09-29'          ],
    [1, 'simple datetime', '2020-09-29 14:37:03', '2020-09-29 14:37:03' ],
    [0, 'invalid date',    '1234', "Invalid date '1234' for column2 (long). Please enter as yyyy-MM-dd."],
];

### the default value of 'is_internal', 'is_internal_type', 'include_time', 'is_userinput'

my $column3 = $sheet->layout->column_create({
    type          => 'createddate',
    name          => 'column3 (long)',
    name_short    => 'column3',
});
logline;

ok  $column3->is_internal,      "default is_internal";
ok  $column3->is_internal_type, "default is_internal_type";
ok  $column3->include_time,     "default include_time";
ok !$column3->is_userinput,     "default is_userinput";

done_testing;
