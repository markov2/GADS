# Check the Createddate column type

use Linkspace::Test;

$::session = test_session;
my $sheet = test_sheet;

my $column1 = $sheet->layout->column_create({
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
isa_ok $column1d, 'Linkspace::Column::Createddate', '...';

#
# is_valid_value
#

sub is_valid_value_test {
    my ($column, $values,$result_value) = @_;
    my $result = try { $column->is_valid_value($values) };
    my $done = $@ ? $@->wasFatal->message : $result;
    $$result_value = $@ ? $@->wasFatal->message : $result;
    ! $@;
}

sub process_test_cases {
    my ($column,@test_cases) = @_;
    my $name=$column->name_short;
    foreach my $test_case (@test_cases) {
        my ($expected_valid,$case_description, $col_intgr_value, $expected_value) = @$test_case;
        my $col_intgr_value_s = $col_intgr_value // '<undef>';
        my $result_value;
        ok $expected_valid == is_valid_value_test($column, $col_intgr_value,\$result_value),
            "... $name validate  $case_description";
        is_deeply $result_value , $expected_value, "... $name value for $case_description";
    }
}

my @test_cases2 = (
    [1, 'simple date',     '2020-09-29',          '2020-09-29'                                                           ],
    [1, 'simple datetime', '2020-09-29 14:37:03', '2020-09-29 14:37:03'                                                  ],
    [0, 'invalid date',    '1234',                'Invalid date \'1234\' for column2 (long). Please enter as yyyy-MM-dd.'],
    [0, 'multivalue date', [1,2],                 'Column \'column2 (long)\' is not a multivalue.'                       ],
    );

my $column2 = $sheet->layout->column_create({
    type          => 'createddate',
    name          => 'column2 (long)',
    name_short    => 'column2',
    is_multivalue => 0,
});
logline;

process_test_cases $column2,@test_cases2;

### the default value of 'is_internal', 'is_internal_type', 'include_time', 'is_userinput'

my $column3 = $sheet->layout->column_create({
    type          => 'createddate',
    name          => 'column3 (long)',
    name_short    => 'column3',
});
logline;

ok $column3->is_internal,"default is_internal";
ok $column3->is_internal_type,"default is_internal_type";
ok $column3->include_time,"default include_time";
ok !$column3->is_userinput,"default is_userinput";

done_testing;
