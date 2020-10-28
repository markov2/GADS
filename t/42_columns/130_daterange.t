# Check the Daterange column type

use Linkspace::Test;

my $sheet   = empty_sheet;
my $layout  = $sheet->layout;

my $column1 = $layout->column_create({
    type          => 'daterange',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_multivalue => 0,
    is_optional   => 0,
});
ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/daterange=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Daterange', '...';

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
isa_ok $column1d, 'Linkspace::Column::Daterange', '...';

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
    [1, 'simple date',            { from => '2020-09-29',to => '2020-09-30' }, 
     { from => '2020-09-29T00:00:00',to => '2020-09-30T00:00:00' }                               ],
    [0, 'invalid from date',      { from => '2020x09-29',to => '2020-09-30' }, 
     'Invalid start date 2020x09-29 for column2 (long). Please enter as yyyy-MM-dd.'             ],
    [0, 'invalid to date',        { from => '2020-09-29',to => '2020-09y30' }, 
     'Invalid end date 2020-09y30 for column2 (long). Please enter as yyyy-MM-dd.'               ],
    [0, 'equal dates',            { from => '2020-09-29',to => '2020-09-29' },
     'Start date must be before the end date for \'column2 (long)\''                             ],
    [0, 'invalid date order',     { from => '2020-09-29',to => '2020-09-28' },
     'Start date must be before the end date for \'column2 (long)\''                             ],
    [1, 'simple datetime',        { from => '2020-09-29 14:37:03', to => '2020-09-29 14:37:04' },
     { from => '2020-09-29T14:37:03', to => '2020-09-29T14:37:04' }                              ],
    [0, 'invalid from datetime',  { from => '2020-09-29T14:37:03', to => '2020-09-29 14:37:04' },
     'Invalid start date 2020-09-29T14:37:03 for column2 (long). Please enter as yyyy-MM-dd.'    ],
    [0, 'invalid to datetime',    { from => '2020-09-29 14:37:03', to => '2020-09-29T14:37:04' },
     'Invalid end date 2020-09-29T14:37:04 for column2 (long). Please enter as yyyy-MM-dd.'      ],
    [0, 'equal datetimes',        { from => '2020-09-29 14:37:03', to => '2020-09-29 14:37:03' },
     'Start date must be before the end date for \'column2 (long)\''                             ],
    [0, 'invalid datetime order', { from => '2020-09-29 14:37:03', to => '2020-09-29 14:37:02' },
     'Start date must be before the end date for \'column2 (long)\''                             ],
    );

my $column2 = $layout->column_create({
    type          => 'daterange',
    name          => 'column2 (long)',
    name_short    => 'column2',
});
logline;

process_test_cases($column2, @test_cases2);

done_testing;
