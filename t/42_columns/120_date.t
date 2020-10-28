# Check the Date column type

use Linkspace::Test;

$::session = test_session;
my $sheet = empty_sheet;

my $column1 = $sheet->layout->column_create({
    type          => 'date',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_multivalue => 0,
    is_optional   => 0,
});
ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/date=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Date', '...';

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
isa_ok $column1d, 'Linkspace::Column::Date', '...';

### setting the value of 'show_datepicker'

my $column2 = $sheet->layout->column_create({
    type          => 'date',
    name          => 'column2 (long)',
    name_short    => 'column2',
    is_multivalue => 1,
    is_optional   => 1,
});
my $path2   = $column2->path;
my $col2_id = $column2->id;
logline;

ok $column2->show_datepicker,"default show_datepicker";
$sheet->layout->column_update($column2, { show_datepicker => 0 });
is logline, "info: Layout $col2_id='$path2' changed fields: options", 'reset show_datepicker logged';
ok !$column2->show_datepicker,"value after reset show_datepicker";
$sheet->layout->column_update($column2, { show_datepicker => 1 });
is logline, "info: Layout $col2_id='$path2' changed fields: options", 'set show_datepicker logged';
ok $column2->show_datepicker,"value after set show_datepicker";

my $column2a = $sheet->layout->column_create({
    type          => 'date',
    name          => 'column2a (long)',
    name_short    => 'column2a',
    is_multivalue => 1,
    is_optional   => 1,
    show_datepicker=> 1,
});
my $path2a   = $column2a->path;
my $col2a_id = $column2a->id;
is logline, "info: Layout created $col2a_id: $path2a", 'creation logged with explicit set show_datepicker';
ok $column2a->show_datepicker,"creation with explicitly set show_datepicker";

my $column2b = $sheet->layout->column_create({
    type          => 'date',
    name          => 'column2b (long)',
    name_short    => 'column2b',
    is_multivalue => 1,
    is_optional   => 1,
    show_datepicker=> 0,
});
my $path2b   = $column2b->path;
my $col2b_id = $column2b->id;
is logline, "info: Layout created $col2b_id: $path2b", 'creation logged with explicit clear show_datepicker';
ok !$column2b->show_datepicker,"creation with explicitly cleared show_datepicker";

### setting the value of 'default_today' = false

my $column3 = $sheet->layout->column_create({
    type          => 'date',
    name          => 'column3 (long)',
    name_short    => 'column3',
    is_multivalue => 1,
    is_optional   => 1,
});
my $path3   = $column3->path;
my $col3_id = $column3->id;
logline;

ok !$column3->default_today,"default default_today";
$sheet->layout->column_update($column3, { default_today => 0 });
is logline, "info: Layout $col3_id='$path3' changed fields: options", 'reset default_today logged';
ok !$column3->default_today,"value after reset default_today";
$sheet->layout->column_update($column3, { default_today => 1 });
is logline, "info: Layout $col3_id='$path3' changed fields: options", 'set default_today logged';
ok $column3->default_today,"value after set default_today";

my $column3a = $sheet->layout->column_create({
    type          => 'date',
    name          => 'column3a (long)',
    name_short    => 'column3a',
    is_multivalue => 1,
    is_optional   => 1,
    default_today => 1,
});
my $path3a   = $column3a->path;
my $col3a_id = $column3a->id;

is logline, "info: Layout created $col3a_id: $path3a", '... logged';
ok $column3a->default_today, "creation with explicitly set default_today";

my $column3b = $sheet->layout->column_create({
    type          => 'date',
    name          => 'column3b (long)',
    name_short    => 'column3b',
    is_multivalue => 1,
    is_optional   => 1,
    default_today => 0,
});
my $path3b   = $column3b->path;
my $col3b_id = $column3b->id;
is logline, "info: Layout created $col3b_id: $path3b", 'creation logged with explicit clear default_today';
ok !$column3b->default_today,"creation with explicitly cleared default_today";

#
# is_valid_value
#

sub is_valid_value_test
{   my ($column, $values, $result_value) = @_;
    my $result = try { $column->is_valid_value($values) };
    $$result_value = $@ ? $@->wasFatal->message : $result;
    ! $@;
}

sub process_test_cases($@)
{   my ($column, @test_cases) = @_;
    my $name = $column->name_short;

    foreach my $test_case (@test_cases) {
        my ($expected_valid, $case_description, $col_intgr_value, $expected_value) = @$test_case;
        my $col_intgr_value_s = $col_intgr_value // '<undef>';

        my $result_value;
        ok $expected_valid == is_valid_value_test($column, $col_intgr_value,\$result_value),
            "... $name validate  $case_description";

        is_deeply $result_value , $expected_value, "... $name value for $case_description";
    }
}

my @test_cases4 = (
    [1, 'simple date',     '2020-09-29',          '2020-09-29'                                                           ],
    [1, 'simple datetime', '2020-09-29 14:37:03', '2020-09-29 14:37:03'                                                  ],
    [0, 'invalid date',    '1234',                'Invalid date \'1234\' for column4 (long). Please enter as yyyy-MM-dd.'],
    [0, 'multivalue date', [1,2],                 'Column \'column4 (long)\' is not a multivalue.'                       ],
    );

my $column4 = $sheet->layout->column_create({
    type          => 'date',
    name          => 'column4 (long)',
    name_short    => 'column4',
    is_multivalue => 0,
});
logline;

process_test_cases($column4, @test_cases4);

done_testing;
