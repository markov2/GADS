# Check the Integer column type

use Linkspace::Test;

$::session = test_session;
my $sheet = test_sheet;

my $column1 = $sheet->layout->column_create({
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

isa_ok $column1, 'Linkspace::Column', '...';
isa_ok $column1, 'Linkspace::Column::Enum', '...';

### Enum utils

use Clone qw(clone);

sub enum_dump($@) {
    my ($title, @enumvals) = @_;
    my @lines=();
    push @lines, "$title:\n";
    my $index = 0;
    while ( $index < @enumvals ) {
        my $id=$enumvals[$index]{id} // '<undef>';
        my $value=$enumvals[$index]{value};
        push @lines, "    \[$index\] = { id : $id, value : '$value' }\n";
        $index += 1;
    }
    @lines;
}

sub enum_print($@) {
    my ($title, @enumvals) = @_;
    print enum_dump $title, @enumvals;
}

sub enum_add($$@) {
    my ($id, $value, @enumvals) = @_;
    my %enumval_new = ( 'value' => $value );
    $enumval_new{'id'} = $id if $id;
    push @enumvals, \%enumval_new;
    @enumvals;
}

sub enum_delete_by_index($@) {
    my ($index, @enumvals) = @_;
    splice(@enumvals, $index, 1);
    @enumvals;
}

sub enum_delete_by_value($@) {
    my ($value, @enumvals) = @_;
    grep { $value ne $_->{'value'} } @enumvals;
}

sub enum_delete_by_id($@) {
    my ($id, @enumvals) = @_;
    grep { $id != $_->{'id'} } @enumvals;
}

sub enum_rename_by_index($$@) {
    my ($index, $newvalue, @orig) = @_;
    my @enumvals = @{ clone \@orig };
    $enumvals[$index]{'value'} = $newvalue;
    @enumvals;
}

sub enum_rename_by_value($$@) {
    my ($oldvalue, $newvalue,  @orig) = @_;
    my @enumvals = @{ clone \@orig };
    for my $enum ( @enumvals ) {
        $enum->{'value'} = $newvalue if $enum->{'value'} eq $oldvalue;
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

sub enum_split_array(@) {
    my (@enumvals) = @_;
    my @enumval_values = map $_->{value} , @enumvals;
    my @enumval_ids    = map $_->{id} , @enumvals;
    (\@enumval_values, \@enumval_ids);
}

sub enum_combine_ids_values($$) {
    my ($ids,$values) = @_;
    my @enumvals = ();
    my $index = 0;
    while ( $index < scalar @{ $ids } ) {
        my %enumval = ( 'id' => $ids->[$index], 'value' => $values->[$index] );
        push @enumvals, \%enumval;
        $index += 1;
    }
    @enumvals;
}

sub enum_rorder($$) {
    my ($order, $enumvals) = @_;
    my @reordered = ();
    my $index = 0;
    while ( $index < scalar @{ $order } ) {
        my $org=$order->[$index];
        push @reordered, $enumvals->[$org];
        $index += 1;
    }
    @reordered;
}

sub enum_from_records($) {
    my ($recs) = @_;
    map { 'id' => $_->id, 'value' => $_->value }, @$recs;
}

### Adding enums

my @some_enums = qw/tic tac toe/;
ok $sheet->layout->column_update($column1, { enumvals => \@some_enums }),
    'Insert some enums';
like logline, qr/add enum '\Q$_\E'/, "... log creation of $_"
    for @some_enums;


#TODO: enums tac, toe, other   one delete, one create, other same id
# id's as example, same number is same id.
# test 2a:
#     initial:
#         [0] = { id : 623, value : 'tic'   }
#         [1] = { id : 624, value : 'tac'   }
#         [2] = { id : 625, value : 'toe'   }
#     delete:
#         [0] = { id : 624, value : 'tac'   }
#         [1] = { id : 625, value : 'toe'   }
# 
# test 2b:
#     initial:
#         [0] = { id : 623, value : 'tic'   }
#         [1] = { id : 624, value : 'tac'   }
#         [2] = { id : 625, value : 'toe'   }
#     create:
#         [0] = { id : 623, value : 'tic'   }
#         [1] = { id : 624, value : 'tac'   }
#         [2] = { id : 625, value : 'toe'   }
#         [3] = { id : 723, value : 'other' }
# 
# test 2c:
#     initial:
#         [0] = { id : 623, value : 'tic'   }
#         [1] = { id : 624, value : 'tac'   }
#         [2] = { id : 625, value : 'toe'   }
#     other, same id:
#         [0] = { id : 623, value : 'other' }
#         [1] = { id : 624, value : 'tac'   }
#         [2] = { id : 625, value : 'toe'   }
#
 TODO: {
     local $TODO = 'delete does not work';
     
     my $column2a = $sheet->layout->column_create({
         type          => 'enum',
         name          => 'column2a (long)',
         name_short    => 'column2a',
         is_multivalue => 0,
         is_optional   => 0,
                                                  });
     logline;

     my @some_enums2a = qw/tic tac toe/;
     ok $sheet->layout->column_update($column2a, { enumvals => \@some_enums2a }),
         'Initial enums for test2a';
     logline for @some_enums2a;
     
     my ($enumval_values2a,$enumval_ids2a) = 
         enum_split_array enum_delete_by_value 'tic', enum_from_records $column2a->enumvals;
     
     ok $sheet->layout->column_update($column2a,
                                      { enumvals => $enumval_values2a, 
                                        enumval_ids => $enumval_ids2a }),
         "Delete enum 'tic'";

     #
     # need to inspect single logline
     #
};

 TODO: {
     local $TODO = 'how to add enum is not defined';
     
     my $column2b = $sheet->layout->column_create({
         type          => 'enum',
         name          => 'column2b (long)',
         name_short    => 'column2b',
         is_multivalue => 0,
         is_optional   => 0,
                                                  });
     logline;

     my @some_enums2b = qw/tic tac toe/;
     ok $sheet->layout->column_update($column2b, { enumvals => \@some_enums2b }),
         'Initial enums for test2b';
     logline for @some_enums2b;
     
     my @some_enums2b_add1 = qw/tic tac toe other/;
     ok $sheet->layout->column_update($column2b, { enumvals => \@some_enums2b_add1 }),
         'Adding other with original';
     
     my @some_enums2b_add2 = qw/tic tac toe other/;
     ok $sheet->layout->column_update($column2b, { enumvals => \@some_enums2b_add2 }),
         'Added other';
     
     #
     # need to inspect single logline
     #
};

my $column2c = $sheet->layout->column_create({
    type          => 'enum',
    name          => 'column2c (long)',
    name_short    => 'column2c',
    is_multivalue => 0,
    is_optional   => 0,
                                             });
logline;

my @some_enums2c = qw/tic tac toe/;
ok $sheet->layout->column_update($column2c, { enumvals => \@some_enums2c }),
    'Initial enums for test2c';
logline for @some_enums2c;

my ($enumval_values2c,$enumval_ids2c) = 
    enum_split_array enum_rename_by_value 'tic', 'other', 
    enum_from_records $column2c->enumvals;

ok $sheet->layout->column_update($column2c,
                                 { enumvals => $enumval_values2c, 
                                   enumval_ids => $enumval_ids2c }),
    'Rename enum \'tic\' to \'other\'';
like logline, qr/rename enum 'tic' to 'other'/, "... log rename of \'tic\'";

#TODO: enum rename: the id is refers to a different name
# id's as example, same number is same id.
# test 3:
#     initial:
#         [0] = { id : 623, value : 'tic'     }
#         [1] = { id : 624, value : 'tac'     }
#         [2] = { id : 625, value : 'toe'     }
#     rename:
#         [0] = { id : 623, value : 'tic'     }
#         [1] = { id : 624, value : 'tac-new' }
#         [2] = { id : 625, value : 'toe'     }
# 
my $column3 = $sheet->layout->column_create({
    type          => 'enum',
    name          => 'column3 (long)',
    name_short    => 'column3',
    is_multivalue => 0,
    is_optional   => 0,
                                            });
logline;

my @some_enums3 = qw/tic tac toe/;
ok $sheet->layout->column_update($column3, { enumvals => \@some_enums3 }),
    'Initial enums for test3';
logline for @some_enums3;

my @expected_value3 = enum_rename_by_value 'tac', 'tac-new', 
    enum_from_records $column3->enumvals;
my ($enumval_values3,$enumval_ids3) = enum_split_array @expected_value3;

ok $sheet->layout->column_update($column3,
                                 { enumvals => $enumval_values3, 
                                   enumval_ids => $enumval_ids3 }),
    'Rename enum \'tac\' to \'tac-new\'';
like logline, qr/rename enum 'tac' to 'tac-new'/, "... log rename of \'tac\'";

my @result_value3 = enum_from_records $column3->enumvals;

is_deeply \@result_value3, \@expected_value3, 
    '... result of rename enum \'tac\' to \'tac-new\'';

#TODO: ->enumvals(include_deleted)   when Enum datun can be created
# id's as example, same number is same id.
# test 4:
#     initial:
#         [0] = { id : 623, value : 'tic'     }
#         [1] = { id : 624, value : 'tac'     }
#         [2] = { id : 625, value : 'toe'     }
# 
my $column4 = $sheet->layout->column_create({
    type          => 'enum',
    name          => 'column4 (long)',
    name_short    => 'column4',
    is_multivalue => 0,
    is_optional   => 0,
                                            });
logline;
my @some_enums4 = qw/tic tac toe/;
ok $sheet->layout->column_update($column4, { enumvals => \@some_enums4 }),
    'Initial enums for test4';
logline for @some_enums4;

my ($enumval_values4,$enumval_ids4) = 
    enum_split_array enum_delete_by_value 'tic', enum_from_records $column4->enumvals;

ok $sheet->layout->column_update($column4,
                                 { enumvals => $enumval_values4, 
                                   enumval_ids => $enumval_ids4 }),
    'Delete enum \'tic\'';
logline;
#
# try printing with deleted enumns to define test...
#
enum_print 'include_deleted', enum_from_records $column4->enumvals(include_deleted => 1);

#TODO: ->enumvals(order => 'asc')
#TODO: ->enumvals(order => 'desc')
#TODO: ->enumvals(order => 'error')
# id's as example, same number is same id.
# test 5:
#     initial:
#         [0] = { id : 623, value : 'tic'     }
#         [1] = { id : 624, value : 'tac'     }
#         [2] = { id : 625, value : 'toe'     }
# 
my $column5 = $sheet->layout->column_create({
    type          => 'enum',
    name          => 'column5 (long)',
    name_short    => 'column5',
    is_multivalue => 0,
    is_optional   => 0,
                                            });
logline;
my @some_enums5 = qw/tic tac toe/;
ok $sheet->layout->column_update($column5, { enumvals => \@some_enums5 }),
    'Initial enums for enumvals sorted';
logline for @some_enums5;

my @enumvals5 = enum_from_records $column5->enumvals;

my @order5_asc = ( 1, 0, 2 );
my @expected_value5_asc = enum_rorder \@order5_asc, \@enumvals5;
my @result_value5_asc = enum_from_records $column5->enumvals(order => 'asc');
is_deeply \@result_value5_asc, \@expected_value5_asc, '... result of enumvals sort asc';

my @order5_desc = ( 2, 0, 1 );
my @expected_value5_desc = enum_rorder \@order5_desc, \@enumvals5;
my @result_value5_desc = enum_from_records $column5->enumvals(order => 'desc');
is_deeply \@result_value5_desc, \@expected_value5_desc, '... result of enumvals sort desc';

my @order5_error = ( 0, 1, 2 );
my @expected_value5_error = enum_rorder \@order5_error, \@enumvals5;
my @result_value5_error = enum_from_records $column5->enumvals(order => 'error');
is_deeply \@result_value5_error, \@expected_value5_error, 
    '... identity result of enumvals sort error';

#TODO: ->random
# id's as example, same number is same id.
# test 6:
#     initial:
#         [0] = { id : 623, value : 'tic'     }
#         [1] = { id : 624, value : 'tac'     }
#         [2] = { id : 625, value : 'toe'     }
#     random:
#         one of 'tic', 'tac', 'toe'?
# 
my $column6 = $sheet->layout->column_create({
    type          => 'enum',
    name          => 'column6 (long)',
    name_short    => 'column6',
    is_multivalue => 0,
    is_optional   => 0,
                                            });
logline;
my @some_enums6 = qw/tic tac toe/;
ok $sheet->layout->column_update($column6, { enumvals => \@some_enums6 }),
    'Initial enums for enumvals sorted';
logline for @some_enums6;

ok $column6->random,'... random should return something, don\'t know what';

#TODO: ->_is_valid_value
# id's as example, same number is same id.
# test 7:
#     initial:
#         [0] = { id : 623, value : 'tic'     }
#         [1] = { id : 624, value : 'tac'     }
#         [2] = { id : 625, value : 'toe'     }
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
        my ($expected_valid,$case_description, $col_id_value, $expected_value) = @$test_case;
        my $col_id_value_s = $col_id_value // '<undef>';
        my $result_value;
        ok $expected_valid == is_valid_value_test($column, $col_id_value,\$result_value),
            "... $name validate  $case_description";
        is_deeply $result_value , $expected_value, "... $name value for $case_description";
    }
}
my @test_cases7 = (
    [1, 'valid enum',   'tac',     '<will be patched>'                                       ],
    [0, 'invalid enum', 'invalid', 'Enum name \'invalid\' not a known for \'column7 (long)\''],
    [0, 'empty enum',   '',        'Enum name \'\' not a known for \'column7 (long)\''       ],
    [0, 'undef enum',   undef,     'Column \'column7 (long)\' requires a value.'             ],
    [0, 'multivalue',   ['tac','toe'], 'Column \'column7 (long)\' is not a multivalue.'      ],
    );

my $column7 = $sheet->layout->column_create({
    type          => 'enum',
    name          => 'column7 (long)',
    name_short    => 'column7',
    is_multivalue => 0,
    is_optional   => 0,
                                            });
logline;
my @some_enums7 = qw/tic tac toe/;
ok $sheet->layout->column_update($column7, { enumvals => \@some_enums7 }),
    'Initial enums for is_valid_value';
logline for @some_enums7;

my @enumvals7 = enum_from_records $column7->enumvals;
$test_cases7[0][3]=$enumvals7[1]{'id'}; # just patch the correct id in the testcases

process_test_cases($column7, @test_cases7);

#TODO: ->export_hash
# id's as example, same number is same id.
# test 8:
#     initial:
#         [0] = { id : 623, value : 'tic'     }
#         [1] = { id : 624, value : 'tac'     }
#         [2] = { id : 625, value : 'toe'     }
# 
my $column8 = $sheet->layout->column_create({
    type          => 'enum',
    name          => 'column8 (long)',
    name_short    => 'column8',
    is_multivalue => 0,
    is_optional   => 0,
                                            });
logline;
my @some_enums8 = qw/tic tac toe/;
ok $sheet->layout->column_update($column8, { enumvals => \@some_enums8 }),
    'Initial enums for enumvals sorted';
logline for @some_enums8;

my @enumvals8 = enum_from_records $column8->enumvals;

ok ! $column8->export_hash,'... export hash should return something, don\'t know what';

#TODO: ->additional_pdf_export
#TODO: ->export_hash
#TODO: ->import_hash

done_testing;

