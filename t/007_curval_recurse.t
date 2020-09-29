use Linkspace::Test;

# Create a recursive calc situation, and check that we don't get caught in a
# loop (in which case this test will never finish)

my $curval_sheet = make_sheet 2;

my $sheet   = make_sheet 1,
    rows             => [],
    curval_sheet     => $curval_sheet,
    curval_columns   => [ 'string1' ],
    calc_return_type => 'string',
    calc_code        => qq{function evaluate (L1curval1)
        -- Check that we can recurse into values as far as the
        -- own record's string value but not its curval
        if L1curval1.field_values.L2autocur1[1].field_values.L1string1 == "foo"
            and L1curval1.field_values.L2autocur1[1].field_values.L1curval1 == nil
        then
            return "Test passed"
        else
            return "Unexpected values: "
                .. L1curval1.field_values.L2autocur1[1].field_values.L1string1
                .. L1curval1.field_values.L2autocur1[1].field_values.L1curval1
        end
    end},
);
my $layout  = $sheet->layout;

# Add autocur and calc of autocur to curval sheet, to check that gets
# updated on main sheet write
my $autocur = $curval_sheet->layout->column_create({
    type => 'autocur',
    refers_to_sheet   => $sheet,
    related_column    => 'curval1',
    curval_columns    => [ 'string1' ],
);

my $calc_recurse = $curval_sheet->layout->column_create({
    name        => 'calc_recurse',
    name_short  => 'calc_recurse',
    return_type => 'integer',
    code        => "function evaluate (L2autocur1) \n return 450 \nend",
);

my $row1 = $sheet->content->row_create;
$row1->revision_create({ curval1 => 1, string1 => 'foo' });

my $row1b = $sheet->content->row($row1->current_id);
is $row1b->cell('calc1'), "Test passed", "Calc evaluated correctly";
is $row1b->cell('curval1'), "Foo", "Curval correct in record";

my $curval_sheet2 = make_sheet 3,
    rows => [{ string1 => 'FooBar1' }];

my $curval = $curval_sheet->layout->column_create({
   type            => 'curval',
   name            => 'Subcurval',
   name_short      => 'L2curval1',
   refers_to_sheet => $curval_sheet2,
   curval_columns  => [ 'string1' ],
   permissions => [ $sheet->group => $sheet->default_permissions ];

my $row2 = $sheet->content->row(1);   #XXX == $row1?
$row2->cell_update({ curval1 => 4, integer1 => 333 });

my $calc_curval = $sheet->layout->column_create({
    type => 'calc',
    name        => 'calc_curval',
    name_short  => 'calc_curval',
    return_type => 'string',
    code        => qq{function evaluate (L1curval1)
        return L1curval1.field_values.L2curval1.field_values.L3string1
    end},
    permissions => [ $sheet->group => $sheet->default_permissions ],
);

my $row2b = $sheet->content->row($row1->current_id);  #XXX
is $row2b->cell($calc_curval), "FooBar1",
    "Values within values of curval code is correct";

done_testing;
