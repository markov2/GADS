# Check the Integer column type

use Linkspace::Test;

my $sheet = test_sheet;

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

sub is_valid_value_test {
    my ($column,$values)=(shift,shift);
    my $tested=1;
    try { 
        $column->is_valid_value($values);
    };
    if ($@) {
        $tested=0;
    }
    $tested
}

sub is_valid_value_value {
    my ($column,$values)=(shift,shift);
    my $result;
    try { 
        $result=$column->is_valid_value($values);
    };
    if ($@) {
        $result=$@->wasFatal->message;
    }
    $result;
}

my @test_multivalue_valid1 = [ 0, 1,3];
my @test_cases1 = (
    [1, '18',    '18'],
    [0, 'abc',   '\'abc\' is not a valid integer for \'column1 (long)\''],
    [1,  '-123', '-123'],
    [1,  '+234', '+234'],
    [0, '',      '\'\' is not a valid integer for \'column1 (long)\''],
    [1,  ' 5',   '5'],
    [1,  '6 ',   '6'],
    [0, undef,   'Column \'column1 (long)\' requires a value.'],
    );

foreach my $test_case1 ( @test_cases1) {
    my ($expected_valid, $col_int_value,$expected_value)=@{$test_case1};
    my $col_int_value_s=defined $col_int_value?$col_int_value:"<undef>";
    my $test_valid=is_valid_value_test( $column1,$col_int_value);
    ok $test_valid==$expected_valid, "... test: value=\"$col_int_value_s\", expected_valid=\"$expected_valid\", test_valid=\"$test_valid\"";
    my $test_value=is_valid_value_value( $column1,$col_int_value);
    is $test_value ,$expected_value, "... test value";
}

my $test_valid1=is_valid_value_test( $column1,@test_multivalue_valid1);
ok ! $test_valid1, "... test_multivalue_valid";

#
# optional and multivalue
#

my $column2 = $sheet->layout->column_create({
    type          => 'intgr',
    name          => 'column2 (long)',
    name_short    => 'column2',
    is_multivalue => 1,
    is_optional   => 1,
});
logline;

my @test_multivalue_valid2 = [ 0, 1,3];
my @test_multivalue_invalid2 = [ 0, 1,'abc'];
my @test_multivalue_undef2 = [ 1, undef,2];
my @test_cases2 = (
    [1, '18',    '18'],
    [0, 'abc',   '\'abc\' is not a valid integer for \'column2 (long)\''],
    [1,  '-123', '-123'],
    [1,  '+234', '+234'],
    [0, '',      '\'\' is not a valid integer for \'column2 (long)\''],
    [1,  ' 5',   '5'],
    [1,  '6 ',   '6'],
    [1, undef,   []],
    );

foreach my $test_case2 ( @test_cases2) {
    my ($expected_valid, $col_int_value,$expected_value)=@{$test_case2};
    my $col_int_value_s=defined $col_int_value?$col_int_value:"<undef>";
    my $test_valid=is_valid_value_test( $column2,$col_int_value);
    ok $test_valid==$expected_valid, "... test: value=\"$col_int_value_s\", expected_valid=\"$expected_valid\", test_valid=\"$test_valid\"";
    my $test_value=is_valid_value_value( $column2,$col_int_value);
    is_deeply $test_value ,$expected_value, "... test value";
}

my $test_valid2=is_valid_value_test( $column2,@test_multivalue_valid2);
ok !$test_valid2, "... test_multivalue_valid";




#my $test_value1=is_valid_value_value( $column1,$col_int_value);
#is $test_value ,$expected_value, "... test value";

#ok $column1->is_valid_value(@test_multivalue_valid),"... valid multivalue";

#ok ! $column1->is_valid_value(@test_multivalue_invalid),"... invalid multivalue";
#ok ! $column1->is_valid_value(@test_multivalue_undef),"... valid undef multivalue";
#
#
#my $column2 = $sheet->layout->column_create({
#    type       => 'intgr',
#    name_short => 'column2',
#    is_optional => 0,
#});
#
#foreach my $test_case ( @test_cases) {
#    my ($col_int_valid, $col_int_value)=@{$test_case};
#    my $col_int_value_s=defined $col_int_value?$col_int_value:"<undef>";
#    ok $column1->is_valid_value($col_int_value, fatal => 0)==$col_int_valid, 
#        "... valid_value value=$col_int_value_s: valid=$col_int_valid";
#}
#


# export_hash

done_testing;
