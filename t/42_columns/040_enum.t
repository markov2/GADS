# Check the Integer column type

use Linkspace::Test;
use Clone      qw(clone);
use List::Util qw(min max);

$::session = test_session;

my $sheet = test_sheet;
my $layout = $sheet->layout;

my $column1 = $layout->column_create({
    type          => 'enum',
    name          => 'column1 (long)',
    name_short    => 'column1',
    is_multivalue => 0,
    is_optional   => 0,
});

ok defined $column1, 'Created column1';
my $col1_id = $column1->id;

my $path1   = $column1->path;
is $path1, $sheet->path.'/enum=column1', '... check path';
is logline, "info: Layout created $col1_id: $path1", '... creation logged';

is $column1->as_string, <<'__STRING', '... as string';
enum             column1
    default ordering: position
__STRING

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Enum', '...';

ok   $column1->can_multivalue, '... can multivalue';
ok ! $column1->is_internal, '... not internal';

### Enum utils

sub enum_add($$@) {
    my ($id, $value, @enumvals) = @_;
    my %enumval_new = (value => $value);
    $enumval_new{id} = $id if $id;
    push @enumvals, \%enumval_new;
    @enumvals;
}

sub enum_delete_by_index($@) {
    my ($index, @enumvals) = @_;
    splice @enumvals, $index, 1;
    @enumvals;
}

sub enum_delete_by_value($@) {
    my ($value, @enumvals) = @_;
    grep { $value ne $_->{value} } @enumvals;
}

sub enum_delete_by_id($@) {
    my ($id, @enumvals) = @_;
    grep { $id != $_->{id} } @enumvals;
}

sub enum_rename_by_index($$@) {
    my ($index, $newvalue, @orig) = @_;
    my @enumvals = @{ clone \@orig };
    $enumvals[$index]{value} = $newvalue;
    @enumvals;
}

sub enum_rename_by_value($$@) {
    my ($oldvalue, $newvalue,  @orig) = @_;
    my @enumvals = @{ clone \@orig };
    for my $enum ( @enumvals ) {
        $enum->{value} = $newvalue if $enum->{value} eq $oldvalue;
    }
    @enumvals;
}

sub enum_rename_by_id($$@) {
    my ($id, $newvalue, @orig) = @_;
    my @enumvals = @{ clone \@orig };
    for my $enum ( @enumvals ) {
        $enum->{value} = $newvalue if $enum->{id} eq $id;
    }
    @enumvals;
}

sub enum_to_vals_ids(@) {
    +{ enumvals    => [ map $_->{value}, @_ ],
       enumval_ids => [ map $_->{id}, @_ ],
    };
}

sub enum_combine_ids_values($$) {
    my ($ids, $values) = @_;
    my @enumvals;
    my $index = 0;
    while($index < @$ids) {
        push @enumvals, { id => $ids->[$index], value => $values->[$index] };
        $index += 1;
    }
    @enumvals;
}

sub enum_reorder($@) {
    my ($order, @enumvals) = @_;
    my @reordered;
    my $index = 0;
    while( $index < @$order) {
        my $org = $order->[$index];
        push @reordered, $enumvals[$org];
        $index += 1;
    }
    @reordered;
}

sub enum_from_records($) {
    my ($recs) = @_;
    map +{ id => $_->id, value => $_->value }, @$recs;
}

sub enum_from_column($) {
    my ($column) = @_;
    map { id => $_->id, value => $_->value }, @{$column->enumvals};
}

sub initial_column($) {
    my ($name) = @_;
    my $column = $layout->column_create({
        type          => 'enum',
        name          => $name.' (long)',
        name_short    => $name,
        is_multivalue => 0,
        is_optional   => 0,
    });
    logline;

    my @some_enums = qw/tic tac toe/;
    ok $layout->column_update($column, { enumvals => \@some_enums } ), 'Initial enums for '.$name;
    logline for @some_enums;
    $column;
}


### Adding enums

my @some_enums = qw/tic tac toe/;
ok $layout->column_update($column1, { enumvals => \@some_enums }), 'Insert some enums';
like logline, qr/add enum '\Q$_\E'/, "... log creation of $_"
    for @some_enums;

#
# enums tac, toe, other  one delete, one create, other same id (keep_unused)
#

### delete 'tic'

my $column2a = initial_column 'column2a';
my @expected_value2a = enum_delete_by_value 'tic', enum_from_column $column2a;
ok $layout->column_update($column2a, enum_to_vals_ids(@expected_value2a), keep_unused => 1),
    'Withdraw enum \'tic\'';
like logline, qr/withdraw option 'tic'/, '... log withdrawal of \'tic\'';
my @result_value2a = enum_from_column $column2a;
is_deeply \@result_value2a, \@expected_value2a, '... result of withdrawal \'tic\'';

is $column2a->as_string, <<'__STRING', '... as string';
enum             column2a
    default ordering: position
      1   tac
      2   toe
      3 D tic
__STRING

### add 'other'

my $column2b = initial_column 'column2b';
my @expected_value2b = enum_reorder [0,3,1,2], enum_add undef, 'other', enum_from_column $column2b;
ok $layout->column_update($column2b, enum_to_vals_ids(@expected_value2b), keep_unused => 1),
    'Add new enum \'other\'';
like logline, qr/add enum 'other'/, '... log adding of \'other\'';
my @result_value2b = enum_from_column $column2b;
delete $result_value2b[1]->{id}; # cannot compare id of new enum
is_deeply \@result_value2b, \@expected_value2b, '... result of add \'other\'';

### rename 'tic' to 'other'

my $column2c = initial_column 'column2c';
my @expected_value2c = enum_rename_by_value 'tic', 'other', enum_from_column $column2c;
ok $layout->column_update($column2c, enum_to_vals_ids( @expected_value2c), keep_unused => 1),
    'Rename enum \'tic\' to \'other\'';
like logline, qr/rename enum 'tic' to 'other'/, '... log rename of \'tic\'';
my @result_value2c = enum_from_column $column2c;
is_deeply \@result_value2c, \@expected_value2c, '... result of rename \'tic\' to \'other\'';

is $column2c->as_string, <<'__STRING', '... show';
enum             column2c
    default ordering: position
      1   other
      2   tac
      3   toe
__STRING

### revive deleted enum 'tic'

my $column2d = initial_column 'column2d';
my @expected_value2d = enum_from_column $column2d;
ok $layout->column_update($column2d, enum_to_vals_ids(enum_delete_by_value 'tic', @expected_value2d), keep_unused => 1),
    'Withdraw enum \'tic\'';

is $column2d->as_string, <<'__STRING', '... show';
enum             column2d
    default ordering: position
      1   tac
      2   toe
      3 D tic
__STRING

like logline, qr/withdraw option 'tic'/, '... log withdrawal of \'tic\'';
ok $layout->column_update($column2d, enum_to_vals_ids(@expected_value2d), keep_unused => 1),
    'Revive deleted \'tic\'';
like logline, qr/deleted enum 'tic' revived/, '... log revivication of \'tic\'';
my @result_value2d = enum_from_column $column2d;
is_deeply \@result_value2a, \@expected_value2a, '... result of reuse of deleted \'tic\'';

#
# enumvals(include_deleted)   when Enum datun can be created
#

my $column3 = initial_column 'column3';
my @initial_value3 = enum_from_column $column3;
ok $layout->column_update($column3,
   enum_to_vals_ids(enum_delete_by_value 'tac', @initial_value3), keep_unused => 1),
   'Withdraw enum \'tac\'';
like logline, qr/withdraw option 'tac'/, '... log withdrawal of \'tac\'';
my @expected_value3 = enum_reorder [0,2,1],  @initial_value3;
my @result_value3 = enum_from_records $column3->enumvals(include_deleted => 1);
is_deeply \@result_value3, \@expected_value3, '... \'tac\' visible';

#
# sorting with enumvals: default, 'asc', 'desc', 'error'
#

my $column4 = initial_column 'column4';
my @enumvals4 = enum_from_column $column4;

### order asc

my @expected_value4_asc = enum_reorder [ 1, 0, 2 ], @enumvals4;
my @result_value4_asc = enum_from_records $column4->enumvals(order => 'asc');
is_deeply \@result_value4_asc, \@expected_value4_asc, '... result of enumvals sort asc';

### order desc

my @expected_value4_desc = enum_reorder [ 2, 0, 1 ], @enumvals4;
my @result_value4_desc = enum_from_records $column4->enumvals(order => 'desc');
is_deeply \@result_value4_desc, \@expected_value4_desc, '... result of enumvals sort desc';

### incorrect order specification

eval {
    my @result_value4_error = $column4->enumvals(order => 'error');
};
like $@, qr/"order", "error"/, "... is incorrect order specification";

### _is_valid_value()

sub is_valid_value_test {
    my ($column, $values, $result_value) = @_;
    my $result = try { $column->is_valid_value($values) };
    $$result_value = $@ ? $@->wasFatal->message : $result;
    ! $@;
}

sub process_test_cases {
    my ($column, @test_cases) = @_;
    my $name=$column->name_short;
    foreach my $test_case (@test_cases) {
        my ($expected_valid, $case_description, $col_id_value, $expected_value) = @$test_case;
        my $col_id_value_s = $col_id_value // '<undef>';
        my $result_value;
        ok $expected_valid == is_valid_value_test($column, $col_id_value, \$result_value),
            "... $name validate  $case_description";
        is_deeply $result_value , $expected_value, "... $name value for $case_description";
    }
}
my $column5 = initial_column 'column5';

my @enumvals5 = enum_from_column $column5;
my $invalid_value = max(map $_->{id}, @enumvals5) + 1;

my @test_cases5 = (
    [1, 'valid enum',   'tac',           "$enumvals5[1]{id}"                                     ],
    [0, 'valid id, but invalid enum', $invalid_value,
                                     "Enum ID '$invalid_value' is not known for 'column5 (long)'"],
    [0, 'invalid enum', 'invalid',       "Enum name 'invalid' is not known for 'column5 (long)'" ],
    [0, 'empty enum',   '',              "Enum ID '' is not known for 'column5 (long)'"          ],
    [0, 'undef enum',   undef,           "Column 'column5 (long)' requires a value."             ],
    [0, 'multivalue',   ['tac','toe'],   "Column 'column5 (long)' is not a multivalue."          ],
    );

process_test_cases($column5, @test_cases5);

#
# export_hash
#

my $column6 = initial_column 'column6';
my %expected_value6 = (
  aggregate => undef,
  can_child => 0,
  description => undef,
  display_condition => 'AND',
  enumvals => [ 'tic', 'tac', 'toe' ],
  group_display => undef,
  helptext => undef,
  id => $column6->id,
  instance_id => $sheet->id,
  internal => 0,
  isunique => 0,
  link_parent => undef,
  multivalue => 0,
  name => 'column6 (long)',
  name_short => 'column6',
  optional => 0,
  options => '{}',
  ordering => undef,
  permissions => {},
  position => 11,
  related_field => undef,
  remember => 0,
  textbox => 0,
  topic_id => undef,
  type => 'enum',
  typeahead => 0,
  width => 50
);
is_deeply $column6->export_hash, \%expected_value6, '... result of export_hash';

#
# additional_pdf_export
#

my $column7 = initial_column 'column7';
is_deeply $column7->additional_pdf_export,
          [ 'Select values' => 'tic, tac, toe' ],
          '... result of additional_pdf_export';

done_testing;

