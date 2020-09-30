
use Linkspace::Test;

# Fix all tests for _version_datetime calc
set_fixed_time '10/22/2014 01:00:00', '%m/%d/%Y %H:%M:%S';

my $data = [
    {
        daterange1 => ['2000-10-10', '2001-10-10'],
        curval1    => 1,
        tree1      => 'tree1',
        integer1   => 10,
        date1      => '2016-12-20',
    },
    {
        daterange1 => ['2012-11-11', '2013-11-11'],
        curval1    => 2,
        tree1      => 'tree1',
        integer1   => 10,
    },
];

my $curval_sheet = make_sheet 2, rows => [];

my $sheet         = make_sheet 1,
    rows          => $data,
    user_count    => 2,
    curval_sheet  => curval_sheet,
    curval_fields => [ 'string1', 'date1' ],
    calc_code     => "function evaluate (L1daterange1) \n return L1daterange1.from.epoch \n end",
    calc_return_type => 'date',
);
my $layout       = $sheet->layout;
my $colperms     = [ $sheet->group => $sheet->default_permissions ];

my $autocur1 = $curval_sheet->layout->columns_create({
    type             => 'autocur',
    curval_columns   => [ 'daterange1' ],
    refers_to_sheet  => $sheet,
    related_column   => 'curval1';
);

# Check that numeric return type from calc can be used in another calc
my $calc_integer = $layout->column_create({
    name        => 'calc_integer',
    name_short  => 'calc_integer',
    return_type => 'integer',
    code        => "function evaluate (L1string1) \n return 450 \nend",
    permissions => $colperms,
});

my $calc_numeric = $layout->column_create({
    name        => 'calc_numeric',
    name_short  => 'calc_numeric',
    return_type => 'numeric',
    code        => "function evaluate (L1string1) \n return 10.56 \nend",
    permissions => $colperms,
);

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
        before => '__SERIAL', # __SERIAL replaced by record serial
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
        before => '8',
        after  => '8',
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
        before => '1482883200', # 28th Dec 2016
        after  => '1482883200',
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
        name        => 'error return failed',
        type        => 'Calc',
        code        => "function evaluate (L1daterange1) \n return 'Unable to submit' \nend",
        return_type => 'error',
        is_error    => 'Unable to submit',
    },
    {
        name        => 'error return success',
        type        => 'Calc',
        code        => "function evaluate (L1daterange1) \n return '' \nend",
        return_type => 'error',
        is_error    => '', # No error
        before      => '',
        after       => '',
    },
    {
        name   => 'use date from another calc field',
        type   => 'Calc',
        code   => qq(function evaluate (L1calc1) \n return L1calc1.year \nend),
        before => '2000',
        after  => '2014'
    },
    {
        name   => 'use value from another calc field (integer)', # Lua will bork if calc_integer not proper number
        type   => 'Calc',
        code   => qq(function evaluate (calc_integer) \n if calc_integer > 200 then return "greater" else return "less" end \nend),
        before => 'greater',
        after  => 'greater'
    },
    {
        name   => 'use value from another calc field (numeric)',
        type   => 'Calc',
        code   => qq(function evaluate (calc_numeric) \n if calc_numeric > 100 then return "greater" else return "less" end \nend),
        before => 'less',
        after  => 'less'
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
        after  => '15'
    },
    {
        name   => 'field with created date',
        type   => 'Calc',
        code   => qq(function evaluate (_created) \n return _created.day \nend),
        before => '22',
        after  => '22'
    },
    {
        name   => 'tree node',
        type   => 'Calc',
        code   => qq(function evaluate (L1tree1) \n return L1tree1.value \nend),
        before => 'tree1',
        after  => 'tree3'
    },
    {
        name       => 'blank tree node',
        type       => 'Calc',
        code       => qq(function evaluate (L1tree1) \n return L1tree1.value \nend),
        tree_value => undef,
        before     => 'tree1',
        after      => ''
    },
    {
        name   => 'flatten of hash',
        type   => 'Calc',
        code   => qq(function evaluate (L1tree1) \n return L1tree1 \nend),
        before => qr/HASH/,
        after  => qr/HASH/
    },
    {
        name       => 'flatten of array',
        type       => 'Calc',
        code       => qq(function evaluate (L1tree1) \n a = {} \n a[1] = L1tree1 \n return a \nend),
        before     => qr/HASH/,
        after      => qr/HASH/,
        is_array   => 1,
        multivalues => 1,
    },
    {
        name   => 'autocur',
        type   => 'Calc',
        layout => $curval_sheet->layout,
        record_check => 1,
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
        layout        => $curval_sheet->layout,
        record_check  => 1,
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
        after  => 'Yes'
    },
    {
        # As previous, but curval ID
        name   => 'curval ID passed to Lua as int type not string',
        type   => 'Calc',
        code   => qq(function evaluate (L1curval1) \n if L1curval1.id == 1 or L1curval1.id == 2 then return "Yes" else return "No" end \nend),
        before => 'Yes',
        after  => 'Yes'
    },
);

my $year = 2014; # Ensure that record writes do not go back in time
foreach my $test (@tests)
{
    # Create a calc field that has something invalid in the nested code
    my $layout_code = $test->{layout} || $layout;
    my $code_col = $layout_code->column_create({
        name           => 'code col',
        return_type    => $test->{return_type} || 'string',
        decimal_places => $test->{decimal_places},
        code           => $test->{code},
        is_multivalue  => $test->{multivalue},
        permissions    => $colperms,
    );

    my @results;
    
    # Code values should have been written to database by now
    $ENV{GADS_PANIC_ON_ENTERING_CODE} = 1;

    my $row1 = $sheet->content->row(1);  #XXX any first row
    push @results, $row1;

    # Set env variables to allow record write (after retrieving results)
    $ENV{GADS_PANIC_ON_ENTERING_CODE} = 0;
    $ENV{GADS_NO_FORK} = 1;

    push @results, $sheet->content->row($row1->current_id);

    # Plus new record
    my $row_new = try { $sheet->content->row_create({
        daterange1 => ['2000-10-10', '2001-10-10'],
        date1      => '2016-12-20',
        curval1    => 1,
        tree1      => 10,
        integer1   => 10,
    }) } hide => 'WARNING'; # Hide warnings from invalid calc fields
    $@->reportFatal unless $test->{is_error}; # In case any fatal errors

    if($test->{is_error})
    {
        like($@, qr/Unable to submit/, "Failed to write record with error return type");
        $code_col->delete;
        next;
    }
    elsif(defined $test->{is_error})
    {   ok !$@, "Successfully wrote record without error $@";
    }

    push @results, $sheet->content->row($row_new->current_id);

    foreach my $record (@results)
    {
        my $before = $test->{before};
        my $cid = $record->current_id;
        $before =~ s/__ID/$cid/ unless ref $before eq 'Regexp';
        my $serial = $schema->resultset('Current')->find($cid)->serial;
        # Check that a serial was actually produced, so we're not comparing 2 null values
        ok $serial, "Serial is not blank";

        $before =~ s/__SERIAL/$serial/ unless ref $before eq 'Regexp';
        $before = qr/^$before$/ unless ref $before eq 'Regexp';

        my $record_check;
        if (my $rcid = $test->{record_check})
        {   $record_check = $test->{layout}->sheet->content($rcid);
        }
        else
        {   $record_check = $record;
        }

        my $ref = $test->{return_type} && $test->{return_type} eq 'date' ? 'DateTime' : '';
        is(ref $_, $ref, "Return value is not a reference or correct reference")
            foreach @{$record_check->fields->{$code_col->id}->value};
        like( $record_check->fields->{$code_col->id}->as_string, $before, "Correct code value for test $test->{name} (before)" );

        # Check we can update the record
        set_fixed_time("11/15/$year 01:00:00", '%m/%d/%Y %H:%M:%S');
        $record->fields->{$columns->{daterange1}->id}->set_value(['2014-10-10', '2015-10-10']);
        $record->fields->{$columns->{curval1}->id}->set_value(2)
            unless exists $test->{curval_update} && !$test->{curval_update};
        $record->fields->{$columns->{tree1}->id}->set_value(exists $test->{tree_value} ? $test->{tree_value} : 12);
        $record->user($schema->resultset('User')->find(2));
        try { $record->write } hide => 'WARNING'; # Hide warnings from invalid calc fields
        $@->reportFatal; # In case any fatal errors
        my $after = $test->{after};
        $after =~ s/__ID/$cid/        unless ref $after eq 'Regexp';
        $after =~ s/__SERIAL/$serial/ unless ref $after eq 'Regexp';
        if (my $rcid = $test->{record_check})
        {   $record_check->clear;
            $record_check->find_current_id($rcid);
        }

        $after = qr/^$after$/ unless ref $after eq 'Regexp';
        is(ref $_, $ref, "Return value is not a reference or correct reference")
            foreach @{$record_check->fields->{$code_col->id}->value};
        like( $record_check->fields->{$code_col->id}->as_string, $after, "Correct code value for test $test->{name} (after)" );

        unless ($test->{record_check}) # Test will not work from wrong datasheet
        {
            $schema->resultset('Enumval')->find(12)->update({ deleted => 1 });
            $layout->clear;
            my $current_id = $record->current_id;
            $record->clear;
            $record->find_current_id($current_id);

            $record->cell_update(string1 => 'Foobar'); # Ensure change has happened
            try { $record->write } hide => 'WARNING';
            $@->reportFatal; # In case any fatal errors
            $record->clear;
            $record->find_current_id($current_id);
            like $record->cell($code_col)->as_string, $after,
                "Correct code value for test $test->{name} after enum deletion";
        }

        # Reset values for next test
        $schema->resultset('Enumval')->find(12)->update({ deleted => 0 });
        $layout->clear;
        $year++;
        set_fixed_time("10/22/$year 01:00:00", '%m/%d/%Y %H:%M:%S');
        $record->cell_update(daterange1 => $data->[0]->{daterange1});
        $record->cell_update(curval1 => $data->[0]->{curval1});
        $record->cell_update(string1 => '');
        $record->cell_update(tree1 => 10);

        try { $record->write } hide => 'WARNING'; # Hide warnings from invalid calc fields
        $@->reportFatal; # In case any fatal errors
    }

    # The user of the Record object at this point does not have permission to
    # delete it. Create new object to delete it
    my $record_delete = $sheet->content->row($record_new->current_id);
    $record_delete->purge;

    $code_col->delete;
}

restore_time();

# Set of tests to check multi-value calc returns
{
    # This calc code will return an array with the number of elements being the
    # value of integer1; or, if integer1 is 10 or 11, an array with 2 elements
    # one way round or the other. If the order of array elements changes, then
    # the string value may change but the "changed" status should be false.
    # This is so that when returning a calc based on another multi-value, it
    # doesn't matter if the order of the input changes.
    my $sheet   = make_sheet '8',
        data      => [],
        calc_code => "
            function evaluate (L1integer1)
                a = {}
                if L1integer1 < 10 then
                    for i=1, L1integer1 do
                        a[i] = 10
                    end
                elseif L1integer1 == 10 then
                    return {100, 200}
                else
                    return {200, 100}
                end
                return a
            end
        ",
        calc_return_type => 'string';

    my $int     = $layout->column('integer1');

    $layout->column_update(calc1 => { is_multivalue => 1 });

    my $row = $layout->row_create;

    # First test number of elements being returned and written
    # One element returned
    $row->revision_create({integer1 => 1});

    my $rset = $schema->resultset('Calcval');
    cmp_ok $rset->count, '==', 1, "Correct number of calc values written to database";

    my $datum = $row->cell($calc);
    is $datum->as_string, "10", "Correct multivalue calc value, one element";

    # Now return 2 elements
    is($rset->count, 1, "Second calc value not yet written to database");
    $row->revision_create({integer1 => 2});
    $datum->re_evaluate;

    is($datum->as_string, "10, 10", "Correct multivalue calc value for 2 elements");
    $datum->write_value;

    is($rset->count, 2, "Second calc value written to database");

    # Test changed status of datum. Should only update after change and
    # re-evaluation.  Reset record and reload
    $record->clear;

    $record = $sheet->content->row(1);
    $datum = $record->cell($calc);

    # Third element
    $row->revision_create({integer1 => 3});

    # Not changed to begin with
    ok ! $datum->changed, "Calc value not changed";

    # Now should change
    $datum->re_evaluate;
    ok $datum->changed, "Calc value changed after re-evaluation");
    is($rset->count, 2, "Correct number of database values before write");
    $datum->write_value;
    is($rset->count, 3, "Correct number of database values after write");

    # Set back to one element, check other database values are removed
    $record->cell_update($int => 1);
    $datum->re_evaluate;
    $datum->write_value;

    is($rset->count, 1, "Old calc values deleted from database");

    # Set to value for next set of tests
    $record->cell_update($int => 10, no_alerts => 1);
    is($rset->search({ record_id => 2 })->count, 2, "Correct number of database calc values");

    # Next test that switching array return values does not set changed status
    $record = $layout->row(1);
    $datum = $record->cell($calc);
    $record->cell_update($int => 10);
    $datum->re_evaluate;

    # Not changed from initial write
    ok ! $datum->changed, 0, "Calc value not changed after writing same value";
    is $datum->as_string, "100, 200", "Correct multivalue calc value for int value 10";

    # Switch the return elements
    $record->cell_update($int => 11);
    $datum->re_evaluate;

    ok ! $datum->changed, 0, "Calc datum not changed after switching return elements";
    is $datum->as_string, "200, 100", "Correct multivalue calc value after switching return";

    $datum->write_value;
    is($rset->search({ record_id => 2 })->count, 2, "Correct database values after switch");
}

# More "changed" tests
{
    my $sheet   = make_sheet '42', rows => 0;
    my $layout  = $sheet->layout;

    my $daterange1 = $layout->column('daterange1');
    my $calc1      = $layout->column('calc1');
    my $rag1       = $layout->column('rag1');

    my $record  = $sheet->content->row_create({
        daterange1 => ['2011-10-10','2015-10-10'],
    }, no_alerts => 1);

    my $record_id = $record->current_id;
    is $record->cell($calc1)->as_string, '2011', "Calc initially correct";
    is $record->cell($rag1)->as_string, 'b_red', "Rag initially correct";

#XXX
    $record = $sheet->content($record->current_id);
    ok(!$record->fields->{$calc1_id}->changed, "Calc not changed on load");
    ok(!$record->fields->{$rag1_id}->changed, "Rag not changed on load");
    $record->fields->{$daterange1_id}->set_value(['2011-09-10','2015-10-10']);
    $record->write(no_alerts => 1);
    ok(!$record->fields->{$calc1_id}->changed, "Calc not changed on suitable write");
    ok(!$record->fields->{$rag1_id}->changed, "Rag not changed on suitable write");

    $record->clear;
    $record->find_current_id($record_id);
    $record->fields->{$daterange1_id}->set_value(['2013-09-10','2015-10-10']);
    $record->write(no_alerts => 1);
    ok($record->fields->{$calc1_id}->changed, "Calc changed on suitable write");
    ok($record->fields->{$rag1_id}->changed, "Rag changed on suitable write");

    # Test blank calc values not changing
    $record->clear;
    $record->find_current_id($record_id);
    # First a change to blank
    $record->fields->{$daterange1_id}->set_value(undef);
    $record->write(no_alerts => 1);

    ok($record->fields->{$calc1_id}->changed, "Calc initial changed when set to blank");
    $record->clear;
    $record->find_current_id($record_id);
    # Then a re-evaluation without change
    $record->fields->{$calc1_id}->re_evaluate;
    ok(!$record->fields->{$calc1_id}->changed, "Calc not changed on blank re-evaluation");
    # Now the same with a string return type
    my $calc1 = $columns->{calc1};
    $calc1->return_type('string');
    $calc1->write;
    $layout->clear;
    $record->clear;
    $record->find_current_id($record_id);
    $record->fields->{$calc1_id}->re_evaluate;
    ok(!$record->fields->{$calc1_id}->changed, "Calc not changed after re-evaluation, string return");

    # Test record created calc
    $calc1 = $layout->column_by_name('calc1');
    $calc1->return_type('date');
    $calc1->code("function evaluate (_created) return _created.epoch end");
    $calc1->write;
    $layout->clear;
    $record->find_current_id($record_id);
    $record->fields->{$calc1_id}->re_evaluate;
    ok(!$record->fields->{$calc1_id}->changed, "Date created code not changed after re-evaluation");
}

{
    # Attempt to create additional calc field separately.
    # This has been known to cause errors with $layout not
    # being updated properly

    # First try with invalid function
    my $calc2_col = try { $layout->column_create({
        name   => 'calc2',
        code   => "foobar evaluate (L1curval)",
    ) };
    like $@, qr/Invalid code definition/,
       "Failed to write calc field with invalid function";

#XXX
    # Then with invalid short name
    $calc2_col = GADS::Column::Calc->new(
        schema => $schema,
        user   => undef,
        layout => $layout,
        name   => 'calc2',
        code   => "function evaluate (L1curval) \n return L1curval1.value\nend",
    );
    try { $calc2_col->write };
    like( $@, qr/Unknown short column name/, "Failed to write calc field with invalid short names" );

    # Then with short name from other table (invalid)
    $calc2_col = GADS::Column::Calc->new(
        schema => $schema,
        user   => undef,
        layout => $layout,
        name   => 'calc2',
        code   => "function evaluate (L2string1) \n return L2string1\nend",
    );
    try { $calc2_col->write };
    like( $@, qr/It is only possible to use fields from the same table/, "Failed to write calc field with short name from other table" );

    # Create a calc field that has something invalid in the nested code
    my $calc_inv_string = GADS::Column::Calc->new(
        schema => $schema,
        user   => undef,
        layout => $layout,
        name   => 'calc3',
        code   => "function evaluate (L1curval1) \n adsfadsf return L1curval1.field_values.L2daterange1.from.year \nend",
    );
    try { $calc_inv_string->write } hide => 'ALL';
    my ($warning) = grep { $_->reason eq 'WARNING' } $@->exceptions;
    like($warning, qr/syntax error/, "Warning received for syntax error in calc");

    # Invalid Lua code with return value not string
    my $calc_inv_int = GADS::Column::Calc->new(
        schema      => $schema,
        user        => undef,
        layout      => $layout,
        name        => 'calc3',
        return_type => 'integer',
        code        => "function evaluate (L1curval1) \n adsfadsf return L1curval1.field_values.L2daterange1.from.year \nend",
    );
    try { $calc_inv_int->write } hide => 'ALL';
    ($warning) = grep { $_->reason eq 'WARNING' } $@->exceptions;
    like($warning, qr/syntax error/, "Warning received for syntax error in calc");

    # Test missing bank holidays
    my $calc_missing_bh = GADS::Column::Calc->new(
        schema      => $schema,
        user        => undef,
        layout      => $layout,
        name        => 'calc3',
        code        => "function evaluate (_id) \n return working_days_diff(2051222400, 2051222400, 'GB', 'EAW') \nend", # Year 2035
    );
    try { $calc_missing_bh->write } hide => 'ALL';
    ($warning) = grep { $_->reason eq 'WARNING' } $@->exceptions;
    like($warning, qr/No bank holiday information available for year 2035/, "Missing bank holiday information warnings for working_days_diff");
    $calc_missing_bh = GADS::Column::Calc->new(
        schema      => $schema,
        user        => undef,
        layout      => $layout,
        name        => 'calc3',
        code        => "function evaluate (_id) \n return working_days_add(2082758400, 1, 'GB', 'EAW') \nend", # Year 2036
    );
    try { $calc_missing_bh->write } hide => 'ALL';
    ($warning) = grep { $_->reason eq 'WARNING' } $@->exceptions;
    like($warning, qr/No bank holiday information available for year 2036/, "Mising bank holiday information warnings for working_days_add");
    $calc_missing_bh->delete;

    # Same for RAG
    my $rag3 = GADS::Column::Rag->new(
        schema => $schema,
        user   => undef,
        layout => $layout,
        name   => 'rag2',
        code   => "
            function evaluate (L1daterange1)
                foobar
            end
        ",
    );
    try { $rag3->write } hide => 'ALL';
    ($warning) = grep { $_->reason eq 'WARNING' } $@->exceptions;
    like($warning, qr/syntax error/, "Warning received for syntax error in rag");
    $rag3->delete;

}

# Set of tests for multivalue fields (with multiple values) that have been
# changed into single value fields. Ideally these would return a consistent
# value type, but given the unique circumstances and the need to support legacy
# code, they will return an array for more than one value, and a scalar for one
# value
foreach my $multi (0..1)
{
    my $data = [
        {
            daterange1 => [ ['2000-10-10', '2001-10-10'], ['2010-01-01', '2011-01-01'] ],
            curval1    => [1, 2],
            tree1      => [10, 11],
            enum1      => [8, 9],
            date1      => ['2016-12-20', '2017-01-01'],
            string1    => ['Foo', 'Bar'],
        },
    ];

    my @tests = (
        {
            col   => 'daterange1',
            code  => '
                function evaluate (L1daterange1)
                    ret = ""
                    for _,val in ipairs(L1daterange1) do
                        ret = ret .. val.value
                    end
                    return ret
                end',
            value => '2000-10-10 to 2001-10-102010-01-01 to 2011-01-01',
        },
        {
            col   => 'curval1',
            code  => '
                function evaluate (L1curval1)
                    ret = ""
                    for _,val in ipairs(L1curval1) do
                        ret = ret .. val.value
                    end
                    return ret
                end',
            value => 'Foo, 2014-10-10Bar, 2009-01-02',
        },
        {
            col   => 'tree1',
            code  => '
                function evaluate (L1tree1)
                    ret = ""
                    for _,val in ipairs(L1tree1) do
                        ret = ret .. val.value
                    end
                    return ret
                end',
            value => 'tree1tree2',
        },
        {
            col   => 'enum1',
            code  => '
                function evaluate (L1enum1)
                    ret = ""
                    for _,val in ipairs(L1enum1.values) do
                        ret = ret .. val.value
                    end
                    return ret
                end',
            value => 'foo3foo2',
        },
        {
            col   => 'date1',
            code  => '
                function evaluate (L1date1)
                    ret = ""
                    for _,val in ipairs(L1date1) do
                        ret = ret .. val.year
                    end
                    return ret
                end',
            value => '20162017',
        },
        {
            col   => 'string1',
            code  => '
                function evaluate (L1string1)
                    ret = ""
                    for _,val in ipairs(L1string1) do
                        ret = ret .. val
                    end
                    return ret
                end',
            value => 'BarFoo',
        },
    );

    my $curval_sheet = make_sheet 2;

    my $sheet        = make_sheet 1,
        rows             => $data,
        multivalue       => 1,
        curval_sheet     => $curval_sheet,
        curval_columns   => [ 'string1', 'date1' ],
        calc_return_type => 'string',
        # Prevent warnings from code that doesn't evaluate correctly
        calc_code        => "function evaluate (L1daterange1) \n return 1234 \n end",
        rag_code         => "function evaluate (L1daterange1) \n return \"green\" \n end",
    );
    my $layout       = $sheet->layout;

    my @cols = qw/daterange1 curval1 tree1 enum1 date1/;
    foreach my $test (@tests)
    {   $layout->column_update($test->{col} => { is_multivalue => 0 });
        $layout->column_update(calc1 => { code => $test->{code} });

        my $row  = $sheet->content->row(3);
        my $cell = $row->cell('calc1');
        $cell->datum->re_evaluate;
        is $cell, $test->{value},
            "Single/multi value code result correct for $test->{col} (multi $multi)";
    }
}

# Ensure that blank and null string fields in the database are treated the same
foreach my $test (qw/string_empty string_null calc_empty calc_null/)
{
    my $sheet   = make_sheet 1,
        rows             => [ { string1 => '' } ],
        calc_code        => 'function evaluate (_id) return "" end',
        calc_return_type => 'string',
    );
    my $layout  = $sheet->layout;

    my $field = $test =~ /string/ ? 'L1string1' : 'L1calc1';
    my $code = "
        function evaluate ($field)
            if L1string1 == nil then
                return \"nil\"
            end
            if L1string1 == \"\" then
                return \"empty\"
            end
            return \"unexpected: \" .. L1string1
        end";

    my $calc2 = $layout->column_create({
       type      => 'calc',
        name   => 'L1calc2',
        code   => $code,
        permissions => $colperms,
    });

    # Manually update database to ensure that both stored empty strings and
    # undefined values are tested
    $schema->resultset('Calcval')->update({
        value_text => $test =~ /null/ ? undef : '',
    });
    $schema->resultset('String')->update({
        value => $test =~ /null/ ? undef : '',
    });

    # Force update of calc2 field
    $calc2->update_cached;

    my $row = $sheet->content->row(1);
    is $row->cell('calc2'), 'nil', "Calc from string correct ($test)";
}

done_testing;
