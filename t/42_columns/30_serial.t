# Check the Serial column type

use Linkspace::Test;

$::session = test_session;
my $sheet = test_sheet;

my $column1 = $sheet->layout->column_create({
    type          => 'serial',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_multivalue => 0,
    is_optional   => 0,
});
ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/serial=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Serial', '...';

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
isa_ok $column1d, 'Linkspace::Column::Serial', '...';

# is_valid_value

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
        my ($expected_valid,$case_description, $col_serial_value, $expected_value) = @$test_case;
        my $col_serial_value_s = $col_serial_value // '<undef>';
        my $result_value;
        ok $expected_valid == is_valid_value_test($column, $col_serial_value,\$result_value),
            "... $name validate  $case_description";
        is_deeply $result_value , $expected_value, "... $name value for $case_description";
    }
}

my @test_cases1 = (
    [1, 'normal id',                            '18',     '18'                                            ],
    [0, 'invalid id',                           'abc',    '\'abc\' is not a valid SERIAL'                 ],
    [0, 'negative number',                      '-123',   '\'-123\' is not a valid SERIAL'                ],
    [0, 'postive number',                       '+234',   '\'+234\' is not a valid SERIAL'                ],
    [0, 'empty string',                         '',       '\'\' is not a valid SERIAL'                    ],
    [1, 'leading space',                        ' 5',     '5'                                             ],
    [1, 'trailing space',                       '6 ',     '6'                                             ],
    [1, 'multiple leading and trailing spaces', '  78  ', '78'                                            ],
    [0, 'number containing a space',            '67 89',  '\'67 89\' is not a valid SERIAL'               ],
    [0, 'optional value',                       undef,    'Column \'column1 (long)\' requires a value.'   ],
    [0, 'multivalue',                           [1,2],    'Column \'column1 (long)\' is not a multivalue.'],
    );

process_test_cases($column1, @test_cases1);

#
# optional and multivalue
#

my $column2 = $sheet->layout->column_create({
    type          => 'serial',
    name          => 'column2 (long)',
    name_short    => 'column2',
    is_multivalue => 1,
    is_optional   => 1,
});
logline;

my @test_cases2 = (
    [1, 'normal number',                        '18',            '18'                             ],
    [0, 'invalid number',                       'abc',           '\'abc\' is not a valid SERIAL'  ],
    [0, 'negative number',                      '-123',          '\'-123\' is not a valid SERIAL' ],
    [0, 'postive number',                       '+234',          '\'+234\' is not a valid SERIAL' ],
    [0, 'empty string',                         '',              '\'\' is not a valid SERIAL'     ],
    [1, 'leading space',                        ' 5',            '5'                              ],
    [1, 'trailing space',                       '6 ',            '6'                              ],
    [1, 'multiple leading and trailing spaces', '  78  ',        '78'                             ],
    [0, 'number containing a space',            '67 89',         '\'67 89\' is not a valid SERIAL'],
    [1, 'optional value',                       undef,           []                               ],
    [1, 'multivalue',                           [1, 2],          [1,2]                            ],
    [0, 'invalid number in multivalue',         [12, 34, 'abc'], '\'abc\' is not a valid SERIAL'  ],
    [1, 'undefined number in multivalue',       [56, undef,79],  [56, 79]                         ],
    );

process_test_cases($column2, @test_cases2);

#is_deeply $column1->export_hash, {},  "... undef in multi value";
#exclude undefs
#renamed

done_testing;
