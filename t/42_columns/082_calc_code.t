# part 1 of t/007_code.t
use Linkspace::Test;

# Fix all tests for _version_datetime calc
set_fixed_time '10/22/2014 01:00:00', '%m/%d/%Y %H:%M:%S';

my $curval_sheet  = make_sheet;

my @sheet_data = (
  { daterange1 => ['2000-10-10', '2001-10-10'],
    curval1    => $curval_sheet->row_at(1),
    tree1      => 'tree1',
    integer1   => 10,
    date1      => '2016-12-20',
  },
  {
    daterange1 => ['2012-11-11', '2013-11-11'],
    curval1    => $curval_sheet->row_at(2),
    tree1      => 'tree1',
    integer1   => 10,
  }
);

my $sheet         = make_sheet
    curval_columns => [ $curval_sheet->column('string1'), $curval_sheet->column('date1') ],
    calc_return_type => 'date',
    calc_code     => "function evaluate (L1daterange1) \n return L1daterange1.from.epoch \n end",
    rows          => \@sheet_data;

my $layout       = $sheet->layout;

my $user1        = test_user;
my $user2        = make_user 2;

diag "Autocur not yet supported";

=pod

my $autocur1 = $curval_sheet->layout->columns_create({
    type           => 'autocur',
    curval_columns => $layout->column('daterange1'),
    related_column => $layout->column('curval1'),
});

=cut

# Check that numeric return type from calc can be used in another calc
my $calc_integer = $layout->column_create({
    type        => 'calc',
    name        => 'calc_integer',
    name_short  => 'calc_integer',
    return_type => 'integer',
    code        => "function evaluate (L1string1) \n return 450 \nend",
});

my $calc_numeric = $layout->column_create({
    type        => 'calc',
    name        => 'calc_numeric',
    name_short  => 'calc_numeric',
    return_type => 'numeric',
    code        => "function evaluate (L1string1) \n return 10.56 \nend",
});

my @tests = (
    {
        name       => 'calc field using curval (full value)',
        type       => 'Calc',
        code       => "function evaluate (L1curval1) \n return L1curval1.value \nend",
        before     => 'Foo, 2014-10-10',
        after      => 'Bar, 2009-01-02',
        multivalues => 1,
    },
    {
        name       => 'calc field using curval (single curval field, standard)',
        type       => 'Calc',
        code       => "function evaluate (L1curval1) \n return L1curval1.field_values.L2string1 \nend",
        before     => 'Foo',
        after      => 'Bar',
        multivalues => 1,
    },
    {
        name       => 'calc field using curval (single curval field, calc)',
        type       => 'Calc',
        code       => "function evaluate (L1curval1) \n return L1curval1.field_values.L2calc1 \nend",
        before     => '2012',
        after      => '2008',
        multivalues => 1,
    },
    {
        name       => 'return array of multivalues',
        type       => 'Calc',
        code       => "function evaluate (_id) \n return {100, 200} \nend",
        before     => '100, 200', # __ID replaced by current ID
        after      => '100, 200',
        multivalues => 1,
    },
    {
        name   => 'serial value of record',
        type   => 'Calc',
        code   => "function evaluate (_serial) \n return _serial \nend",
        before => '__SERIAL', # __SERIAL replaced by real serial
        after  => '__SERIAL',
    },
    {
        name => 'rag from daterange',
        type => 'Rag',
        code   => "
            function evaluate (L1daterange1)
                if L1daterange1 == nil then return end
                if L1daterange1.from.year < 2012 then return 'red' end
                if L1daterange1.from.year == 2012 then return 'amber' end
                if L1daterange1.from.year > 2012 then return 'green' end
            end
        ",
        before => 'b_red',
        after  => 'd_green',
    },
    {
        name => 'working days diff',
        type => 'Calc',
        code   => "
            function evaluate (L1date1)
                if L1date1 == nil then return nil end
                return working_days_diff(L1date1.epoch, 1483488000, 'GB', 'EAW')
            end
        ", # 1483488000 is 4th Jan 2017
        before => 8,
        after  => 8,
    },
    {
        name => 'working days add',
        type => 'Calc',
        code   => "
            function evaluate (L1date1)
                if L1date1 == nil then return nil end
                return working_days_add(L1date1.epoch, 4, 'GB', 'EAW')
            end
        ",
        before => 1482883200, # 28th Dec 2016
        after  => 1482883200,
    },
    {
        name           => 'decimal calc',
        type           => 'Calc',
        code           => "function evaluate (L1daterange1) \n return L1daterange1.from.year / 10 \nend",
        return_type    => 'numeric',
        decimal_places => 1,
        before         => '200.0',
        after          => '201.4',
    },
    {
        name           => 'error return failed',
        type           => 'Calc',
        code           => "function evaluate (L1daterange1) \n return 'Unable to submit' \nend",
        return_type    => 'error',
        expect_error   => 'Unable to submit',
    },
    {
        name           => 'error return success',
        type           => 'Calc',
        code           => "function evaluate (L1daterange1) \n return '' \nend",
        return_type    => 'error',
        expect_error   => '', # No error
        before         => '',
        after          => '',
    },
    {
        name   => 'use date from another calc field',
        type   => 'Calc',
        code   => qq(function evaluate (L1calc1) \n return L1calc1.year \nend),
        before => '2000',
        after  => '2014',
    },
    {
        name   => 'use value from another calc field (integer)', # Lua will bork if calc_integer not proper number
        type   => 'Calc',
        code   => qq(function evaluate (calc_integer) \n if calc_integer > 200 then return "greater" else return "less" end \nend),
        before => 'greater',
        after  => 'greater',
    },
    {
        name   => 'use value from another calc field (numeric)',
        type   => 'Calc',
        code   => qq(function evaluate (calc_numeric) \n if calc_numeric > 100 then return "greater" else return "less" end \nend),
        before => 'less',
        after  => 'less',
    },
    {
        name        => 'calc fields that returns 0 (int)',
        type        => 'Calc',
        code        => "function evaluate (L1curval1) \n return 0 \nend",
        return_type => 'integer',
        before      => '0',
        after       => '0',
    },
    {
        name        => 'calc fields that returns 0 (string)',
        type        => 'Calc',
        code        => "function evaluate (L1curval1) \n return 0 \nend",
        return_type => 'string',
        before      => '0',
        after       => '0',
    },
    {
        name        => 'calc fields that returns 0 (date)',
        type        => 'Calc',
        code        => "function evaluate (L1curval1) \n return 0 \nend",
        return_type => 'date',
        before      => '1970-01-01',
        after       => '1970-01-01',
    },
    {
        name   => 'field with version editor',
        type   => 'Calc',
        code   => qq(function evaluate (_version_user) \n return _version_user.surname \nend),
        before => 'User1',
        after  => 'User2',
    },
    {
        name   => 'field with version editor organisation',
        type   => 'Calc',
        code   => qq(function evaluate (_version_user) \n return _version_user.organisation.name \nend),
        before => 'My Organisation',
        after  => 'My Organisation',
    },
    {
        name   => 'field with version editor department',
        type   => 'Calc',
        code   => qq(function evaluate (_version_user) \n return _version_user.department.name \nend),
        before => 'My Department',
        after  => 'My Department',
    },
    {
        name   => 'field with version date',
        type   => 'Calc',
        code   => qq(function evaluate (_version_datetime) \n return _version_datetime.day \nend),
        before => '22',
        after  => '15',
    },
    {
        name   => 'field with created date',
        type   => 'Calc',
        code   => qq(function evaluate (_created) \n return _created.day \nend),
        before => '22',
        after  => '22',
    },
    {
        name   => 'tree node',
        type   => 'Calc',
        code   => qq(function evaluate (L1tree1) \n return L1tree1.value \nend),
        before => 'tree1',
        after  => 'tree3',
    },
    {
        name       => 'blank tree node',
        type       => 'Calc',
        code       => qq(function evaluate (L1tree1) \n return L1tree1.value \nend),
        tree_value => undef,
        before     => 'tree1',
        after      => '',
    },
    {
        name       => 'flatten of hash',
        type       => 'Calc',
        code       => qq(function evaluate (L1tree1) \n return L1tree1 \nend),
        before     => qr/HASH/,
        after      => qr/HASH/,
    },
    {
        name       => 'flatten of array',
        type       => 'Calc',
        code       => qq(function evaluate (L1tree1) \n a = {} \n a[1] = L1tree1 \n return a \nend),
        before     => qr/HASH/,
        after      => qr/HASH/,
        multivalues => 1,
    },
    {
        name   => 'autocur',
        type   => 'Calc',
        sheet  => $curval_sheet,
        check_rev    => 1,
        code   => qq(function evaluate (L2autocur1)
            return_value = ''
            for _, v in pairs(L2autocur1) do
                return_value = return_value .. v.field_values.L1daterange1.from.year
            end
            return return_value
        end),
        before => '20002000', # Original first record plus new record
        after  => '2000', # Only one referring record after test
    },
    {
        name          => 'autocur code update only',
        type          => 'Calc',
        sheet         => $curval_sheet,
        check_rev     => 1,
        curval_update => 0,
        code          => qq(function evaluate (L2autocur1)
            return_value = ''
            for _, v in pairs(L2autocur1) do
                return_value = return_value .. v.field_values.L1daterange1.from.year
            end
            return return_value
        end),
        before => '20002000', # Original first record plus new record
        after  => '20002014', # One record has daterange updated only
    },
    {
        # In Lua, "10" is not equal to 10
        name   => 'integer passed to Lua as int type not string',
        type   => 'Calc',
        code   => qq(function evaluate (L1integer1) \n if L1integer1 == 10 then return "Yes" else return L1integer1 end \nend),
        before => 'Yes',
        after  => 'Yes',
    },
    {
        # As previous, but curval ID
        name   => 'curval ID passed to Lua as int type not string',
        type   => 'Calc',
        code   => qq(function evaluate (L1curval1) \n if L1curval1.id == 1 or L1curval1.id == 2 then return "Yes" else return "No" end \nend),
        before => 'Yes',
        after  => 'Yes',
    },
);

my $year = 2014; # Ensure that record writes do not go back in time
foreach my $test (@tests)
{   ok 1, "running test $test->{name}";

    if($test->{name} =~ /autocur/)
    {   diag "Autocur not yet supported";
        next;
    }

    # Create a calc field that has something invalid in the nested code
    my $add_to   = $test->{sheet} || $sheet;
    my $code_col = $add_to->layout->column_create({
        name           => 'code col',
        return_type    => $test->{return_type} || 'string',
        decimal_places => $test->{decimal_places},
        code           => $test->{code},
        is_multivalue  => $test->{multivalue},
    });

    my $row1 = $sheet->row_at(1);
    my $rev_previous = $row1->current;

    # Plus new record
    my $rev_new = try { $row1->revisions_create({
        daterange1 => ['2000-10-10', '2001-10-10'],
        date1      => '2016-12-20',
        curval1    => $curval_sheet->row_at(1),
        tree1      => 'tree1',
        integer1   => 10,
    }) } hide => 'WARNING'; # Hide warnings from invalid calc fields

    if($test->{expect_error})
    {   like $@, qr/Unable to submit/, '... expected write failed on return type';
        $code_col->delete;
        next;
    }
    else
    {   $@->reportFatal;  # report unexpected errors
    }

    foreach my $revision ($rev_previous, $rev_new)
    {   my $before = $test->{before};
        $before =~ s/__ID/$row1->id/e  if ref $before ne 'Regexp';

        my $serial = $row1->serial;
        $before =~ s/__SERIAL/$serial/ if ref $before ne 'Regexp';

        $before = qr/^$before$/        if ref $before ne 'Regexp';

        my $check_rev   ;
        if (my $rcid = $test->{check_rev})
        {   $check_rev = $add_to->content($rcid);
        }
        else
        {   $check_rev = $revision;
        }

        my $ref = $test->{return_type} eq 'date' ? 'DateTime' : '';
        is ref $_, $ref, '... return type reference'
            for @{$check_rev->cell($code_col)->value};

        like $check_rev->cell($code_col)->as_string, $before, "... code value (before)";

        # Check we can update the record
        set_fixed_time "11/15/$year 01:00:00", '%m/%d/%Y %H:%M:%S';
 
        my %new_rev = (
             daterange1     => ['2014-10-10', '2015-10-10'],
             tree1          => $test->{tree_value} // 'tree3',
             __version_user => $user2,
        );
        $new_rev{curval1} = $curval_sheet->row_at(2)->id
            unless exists $test->{curval_update} && !$test->{curval_update};

        # Hide warnings from invalid calc fields
        my $new_rev = try { $row1->revision_create(\%new_rev) } hide => 'WARNING';
        $@->reportFatal; # In case any fatal errors

        my $after = $test->{after};
        $after =~ s/__ID/$row1->id/e  if ref $after ne 'Regexp';
        $after =~ s/__SERIAL/$serial/ if ref $after ne 'Regexp';

        $after = qr/^$after$/ unless ref $after eq 'Regexp';
        is ref $_, $ref, "... return value is not a reference or correct reference"
            for @{$check_rev->cell($code_col)->value};

        like $check_rev->cell($code_col)->as_string, $after, "... correct code value (after)";

        unless($test->{check_rev}) # Test will not work from wrong datasheet
        {   $layout->column('enum1')->enum_deleted(12, 1); #XXX which one is 12?  set it deleted
            like $revision->cell($code_col)->as_string, $after,
                "... correct code value after enum deletion";
        }

        # Reset values for next test
        $layout->column('enum1')->enum_deleted(12, 0); #XXX which one is 12?  set undeleted

        $year++;
        set_fixed_time "10/22/$year 01:00:00", '%m/%d/%Y %H:%M:%S';

        try { $row1->revision_create({
            daterange1 => $sheet_data[0]->{daterange1},
            curval1    => $sheet_data[0]->{curval1},
            string1    => '',
            tree1      => 'tree1',
        }) } hide => 'WARNING'; # Hide warnings from invalid calc fields
        $@->reportFatal; # In case any fatal errors
    }

    $code_col->delete;
}


### Attempt to create additional calc field separately.

# First try with invalid function
my $calc2_col = try { $layout->column_create({
    name   => 'calc2',
    code   => "foobar evaluate (L1curval)",
}) };
like $@, qr/Invalid code definition/,
   "Failed to write calc field with invalid function";

# Then with invalid short name
try { $layout->column_create({
    type   => 'calc',
    name   => 'calc2',
    code   => "function evaluate (L1curval) \n return L1curval1.value\nend",
}) };
like $@->wasFatal->message , qr/Unknown short column name/,
      "Failed to write calc field with invalid short names";

# Then with short name from other table (invalid)
try { $layout->column_create({ 
    type => 'calc',
    name => 'calc2',
    code => "function evaluate (L2string1) \n return L2string1\nend",
}) };
like $@, qr/It is only possible to use fields from the same table/,
     "Failed to write calc field with short name from other table";

# Create a calc field that has something invalid in the nested code
try { $layout->column_create({
    type => 'calc',
    name => 'calc3',
    code => "function evaluate (L1curval1) \n adsfadsf return L1curval1.field_values.L2daterange1.from.year \nend",
}) } hide => 'ALL';
my ($warning) = grep $_->reason eq 'WARNING', $@->exceptions;
like $warning, qr/syntax error/, "Warning received for syntax error in calc";

# Invalid Lua code with return value not string
try { $layout->column_create({
    type => 'calc',
    name => 'calc3',
    return_type => 'integer',
    code => "function evaluate (L1curval1) \n adsfadsf return L1curval1.field_values.L2daterange1.from.year \nend",
}) } hide => 'ALL';
($warning) = grep $_->reason eq 'WARNING', $@->exceptions;
like $warning, qr/syntax error/, "Warning received for syntax error in calc";

# Test missing bank holidays
try { $layout->column_create({
    type => 'calc',
    name => 'calc3',
    code => "function evaluate (_id) \n return working_days_diff(2051222400, 2051222400, 'GB', 'EAW') \nend", # Year 2035
}) } hide => 'ALL';
($warning) = grep $_->reason eq 'WARNING', $@->exceptions;
like $warning, qr/No bank holiday information available for year 2035/,
     "Missing bank holiday information warnings for working_days_diff";

try { $layout->column_create({ 
    type => 'calc',
    name => 'calc4',
    code => "function evaluate (_id) \n return working_days_add(2082758400, 1, 'GB', 'EAW') \nend", # Year 2036
}) } hide => 'ALL';
($warning) = grep { $_->reason eq 'WARNING' } $@->exceptions;
like $warning, qr/No bank holiday information available for year 2036/,
    "Mising bank holiday information warnings for working_days_add";

# Same for RAG
try { $layout->column_create({ 
    type => 'rag',
    name => 'rag2',
    code => <<'__CODE' }) } hide => 'ALL';
        function evaluate (L1daterange1)
            foobar
        end
__CODE
($warning) = grep $_->reason eq 'WARNING', $@->exceptions;
like $warning, qr/syntax error/, "Warning received for syntax error in rag";

done_testing;
