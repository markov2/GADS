# Check the String column type

use Linkspace::Test;

$::session = test_session;
my $sheet = test_sheet;

my $column1 = $sheet->layout->column_create({
    type          => 'string',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_textbox    => 0,
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
        my ($expected_valid,$case_description, $col_string_value, $expected_value) = @$test_case;
        my $col_string_value_s = $col_string_value // '<undef>';
        my $result_value;
        ok $expected_valid == is_valid_value_test($column, $col_string_value,\$result_value),
            "... $name validate  $case_description";
        is_deeply $result_value , $expected_value, "... $name value for $case_description";
    }
}

#
#     Replace non-breakable space by space
#     Remove leading empty lines in text box
#     Remove trailing lines containing space only in textbox
#     Remove trailing space in lines in textbox
#     
#     Replace multiple spaces (white space, non-breakable space) by single space
#     Remove leading spaces
#     Remove trailing spaces
#
#     is_textbox: =~ s/\xA0/ /gr =~ s/\A\s*$//mrs =~ s/\s*\z/\n/mrs =~ s/\s+$//gmr
#
#     =~ s/[\xA0\s]+/ /gr =~ s/^ //r =~ s/ $//r;
#

my @test_cases1 = (
    [1, 'normal string',            "from here to there",  "from here to there"                    ],
    [1, 'multiple spaces',          " multiple \t\xA0 \t\xA0spaces   ",  "multiple spaces"         ],
    [1, 'leading space',            " \tleading space",  "leading space"                           ],
    [1, 'leading spaces',           " \tleading spaces",  "leading spaces"                         ],
    [1, 'trailing space',           "multiple trailing spaces \t\xA0",  "multiple trailing spaces" ],
    [1, 'trailing spaces',          "multiple trailing spaces ",  "multiple trailing spaces"       ],
    [1, 'multiple multiple spaces', "multiple  spaces  between",  "multiple spaces between"        ],
    );

process_test_cases($column1, @test_cases1);

#
# textbox, multivalue and optional
#

my $column2 = $sheet->layout->column_create({
    type          => 'string',
    name          => 'column2 (long)',
    name_short    => 'column2',
    is_textbox    => 1,
    is_multivalue => 1,
    is_optional   => 1,
});
logline;

my @test_cases2 = (
    [1, "double normal line", "line1\nline2",  "line1\nline2"                    ],
    [1, "empty lines",  "\n\n\n",          ""         ],
    [1, "leading multiple empty lines",  "\n\n\nline1\nline2",          "line1\nline2"         ],
    [1, "trailing multiple empty lines",  "line1\nline2\n\n\n",         "line1\nline2"         ],
    );

process_test_cases($column2, @test_cases2);

done_testing;
