use Linkspace::Test;

my $plan = {
    string1 => {
        old_as_string => 'foo', # The initial value
        new           => 'bar', # The value it's changed to
        new_as_string => 'bar', # The string representation of the new value
    },
    integer1 => {
        old_as_string  => '100',
        new            => 200,
        new_as_string  => '200',
        addable        => '(+ 25)',
        addable_result => '225',
    },
    enum1 => {
        old_as_string => 'foo1',
        new           => 8,
        new_as_string => 'foo2',
    },
    tree1 => {
        old_as_string => 'tree1',
        new           => 11,
        new_as_string => 'tree2',
    },
    date1 => {
        old_as_string  => '2010-10-10',
        new            => '2011-10-10',
        new_as_string  => '2011-10-10',
        addable        => '+ 1 year',
        addable_result => '2012-10-10',
    },
    daterange1 => {
        old_as_string  => '2000-10-10 to 2001-10-10',
        new            => ['2000-11-11', '2001-11-11'],
        new_as_string  => '2000-11-11 to 2001-11-11',
        filter_value   => '2000-11-11 to 2001-11-11',
        addable        => ['+ 1 week', '+ 5 years'],
        addable_result => '2000-11-18 to 2006-11-11',
    },
    curval1 => {
        old_as_string => 'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012',
        new           => 2,
        new_as_string => 'Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
    },
    person1 => {
        old_as_string => 'User1, User1',
        new           => {
            id       => 2,
            username => 'user2@example.com',
            email    => 'user2@example.com',
            value    => 'User2, User2',

        },
        new_as_string => 'User2, User2',
        new_html_form => 2,
        new_html      => 'User2, User2',
        filter_value  => 2,
    },
    file1 => {
        old_as_string => 'file1.txt',
        new => {
            name     => 'file2.txt',
            mimetype => 'text/plain',
            content  => 'Text file2',
        },
        new_html_form => 2,
        new_as_string => 'file2.txt',
        new_html      => 'file2.txt',
        filter_value  => 2,
    },
    calc1 => {
        filter_value => '2000',
    },
    rag1 => {
        filter_value => 'b_red',
    },
};

my $data = {
    blank => [
        {
            string1    => '',
            integer1   => '',
            enum1      => '',
            tree1      => '',
            date1      => '',
            daterange1 => ['', ''],
            curval1    => '',
            file1      => '',
            person1    => '',
        },
    ],
    changed => [
        {
            string1    => 'foo',
            integer1   => '100',
            enum1      => 7,
            tree1      => 10,
            date1      => '2010-10-10',
            daterange1 => ['2000-10-10', '2001-10-10'],
            curval1    => 1,
            person1    => $user1,
            file1      => {
                name     => 'file1.txt',
                mimetype => 'text/plain',
                content  => 'Text file1',
            },
        },
    ],
    nochange => [
        {
            string1    => 'bar',
            integer1   => '200',
            enum1      => 8,
            tree1      => 11,
            date1      => '2011-10-10',
            daterange1 => ['2000-11-11', '2001-11-11'],
            curval1    => 2,
            person1    => $user2,
            file1      => {
                name     => 'file2.txt',
                mimetype => 'text/plain',
                content  => 'Text file2',
            },
        },
    ],
};

my $sheet_counter = 42;

# First check that we can create new record and access its blank values

foreach my $multivalue (0..1)
{
    my $curval_sheet = make_sheet $sheet_counter++;

    my $sheet = make_sheet $sheet_counter++,
        curval_sheet => $curval_sheet,
        multivalues  => $multivalue;

    my $row = $sheet->content->row_create;

    foreach my $type (keys %$plan)
    {   my $col = $sheet->layout->column($type);
        next if ! $col->is_userinput;

        my $cell = $row->cell($col);
        is $cell->as_string, '', "New record $type is empty string";

        if($col->is_multivalue)
        {   is_deeply $cell->value, [], "Multivalue of new record $type is empty array"
                if $cell->can('value');

            is_deeply $cell->ids, [], "Multivalue of new record $type is empty array"
                if $cell->can('ids');
        }
        else
        {   is $cell->value, undef, "Value of new record $type is undef"
                if $cell->can('value');

            is $$cell->id, undef, "ID of new record $type is undef"
                if $cell->can('id') && $col->type ne 'tree';
        }

        # Check that id_hash can be generated correctly
        is ref $cell->id_hash, 'HASH', "$type has id_hash"
            if $cell->can('id_hash');
    }
}

sub run_test($$$$)
{   my ($multivalue, $test, $arrayref, $deleted) = @_;
    my $curval_sheet = make_sheet $sheet_counter++;

    my $sheet   = make_sheet $sheet_counter++,
        rows         => $data->{$test},
        multivalues  => $multivalue,
        curval_sheet => $curval_sheet,
    );

    #XXX only for this sheet
    $schema->resultset('Enumval')->update({ is_deleted => 1 });
        if $deleted;

    my $page     = $sheet->current;
    my $is_multi = $multivalue ? " for multivalue" : '';
    cmp_ok $page->row_count, '==', 1, "One record in test dataset$is_multi";

    my $row      = $page->row(1);

    foreach my $type (sort keys %$plan)
    {   next if $deleted  && $type !~ /(enum1|tree1)/;
        next if $arrayref && $type eq 'daterange1';

        my $values = $plan->{$type};
        my $column = $layout->column($type);
        my $datum  = $record->cell($column);
        if($column->is_userinput)
        {   if($test eq 'blank')
            {   ok  $datum->is_blank, "$type is blank$is_multi";
            }
            else
            {   ok !$datum->is_blank, "$type is not blank$is_multi";
            }

            my $new    = $values->{new};
            my $change = $arrayref ? [ $new ] : $new;
            $row->cell_update($datum => $change);
        }

        if($test eq 'changed' && !$deleted)
        {
            # Check filter value for normal datum
            my $filter_value = $values->{filter_value} || $values->{new};
            is $datum->filter_value, $filter_value, "Filter value correct for $type";

            # Then create datum as it would be for grouped value and check again
            my $datum_filter = $column->datum_class->new(
                init_value       => [ $filter_value ],
                column           => $datum->column,
            );

            is $datum_filter->filter_value, $filter_value,
                "Filter value correct for $type (grouped datum)";
        }
        next if !$column->is_userinput;

        if ($deleted)
        {
            if ($test eq 'nochange')
            {   ok !$@, "No exception when writing deleted same value with test $test";
            }
            else
            {   # As it stands, tree gets a specific deleted error
                # message, enum just errors as invalid
                my $msg = $type =~ /^tree/ ? qr/has been deleted/ : qr/is not a valid/;
                like $@, $msg, "Unable to write changed value to one that is deleted";
            }
            # We don't have any sensible values to test against,
            # and the subsequent tests are done for a none-deleted
            # value anyway, so skip the rest
            next;
        }
        else
        {   $@->reportAll;
        }

        if($test eq 'blank' || $test eq 'changed')
        {   ok  $datum->changed, "$type has changed$is_multi";
        }
        else
        {   ok !$datum->changed, "$type has not changed$is_multi";
        }

        if($test eq 'changed' || $test eq 'nochange')
        {
            ok( $datum->oldvalue, "$type oldvalue exists$is_multi" );
            my $old = $test eq 'changed' ? $values->{old_as_string} : $values->{new_as_string};
            is $datum->oldvalue && $datum->oldvalue->as_string, $old,
                "$type oldvalue exists and matches for test $test$is_multi";

            my $html_form = $values->{new_html_form} || $values->{new};
            $html_form = [ $html_form ] if ref $html_form ne 'ARRAY';
            is_deeply $datum->html_form, $html_form, "html_form value correct";
        }
        elsif($test eq 'blank')
        {   ok $datum->oldvalue && $datum->oldvalue->is_blank, "$type was blank$is_multi";
        }

        my $new_as_string = $values->{new_as_string};
        is( $datum->as_string, $new_as_string, "$type is $new_as_string$is_multi for test $test" );
        my $new_html = $values->{new_html} || $new_as_string;
        if(ref $new_html eq 'Regexp')
        {   like $datum->html, $new_html, "$type is $new_html$is_multi for test $test";
        }
        else
        {   is $datum->html, $new_html, "$type is $new_html$is_multi for test $test";
        }

        # Check that setting a blank value works
        if ($test eq 'blank')
        {
            if ($arrayref)
            {   $datum->set_value([$data->{blank}->[0]->{$type}]);
            }
            else
            {   $datum->set_value($data->{blank}->[0]->{$type});
            }
            ok( $datum->blank, "$type has been set to blank$is_multi" );
            # Test writing of addable value applied to an blank existing value.
            if(my $addable = $values->{addable})
            {   $datum->set_value($addable, bulk => 1);
                ok $datum->is_blank, "$type is blank after writing addable value$is_multi";
            }
        }
        elsif ($test eq 'changed')
        {   # Doesn't really matter which write test, as long as has value
            if(my $addable = $values->{addable})
            {   $datum->set_value($addable, bulk => 1);
                is $datum->as_string, $values->{addable_result},
                    "$type is correct after writing addable change$is_multi";
            }
        }
    }
}

foreach my $multivalue (0..1)
{   for my $test ('blank', 'nochange', 'changed')
    {   # Values can be set as both array ref and scalar. Test both.
        foreach my $arrayref (0..1)
        {   foreach my $deleted (0..1) # Test for deleted values of field, where applicable
            {   run_test $multivalue, $test, $arrayref, $deleted;
            }
        }
    }
}

# Set of tests to check behaviour when values start as undefined (as happens,
# for example, when a new column is created and not added to existing records)
my $curval_sheet = make_sheet 1;
my $sheet        = make_sheet 2, curval_sheet => $curval_sheet;

foreach my $c (keys %$values)
{   my $column = $columns->{$c};
    $column->is_userinput or next;

    # First check that an empty string replacing the null
    # value counts as not changed
    my $class  = $column->datum_class;
    my $datum = $class->new(
        set_value       => undef,
        column          => $column,
        init_no_value   => 1,
        schema          => $schema,
    );
    $datum->set_value($values->{$c}->{new});
    ok( $datum->changed, "$c has changed" );
    # And now that an actual value does count as a change
    $datum = $class->new(
        set_value       => undef,
        column          => $column,
        init_no_value   => 1,
        schema          => $schema,
    );
    $datum->set_value($data->{blank}->[0]->{$c});
    ok( !$datum->changed, "$c has not changed" );
}


# Test mandatory fields
{
    my $curval_sheet = make_sheet 2;

    my $sheet = make_sheet 1,
        optional     => 0,
        rows         => [],
        curval_sheet => $curval_sheet;
    my $layout = $sheet->layout;

    foreach my $column ($layout->search_columns(userinput => 1))
    {   my $colname = $column->name;
        try { $content->row_create };  #XXX per column?
        like $@, qr/\Q$colname/, "Correctly failed to write without mandatory value";

        # Write a value, so it doesn't stop on same column next time
        $row->cell_update($column, $values->{$colname}->{new});
    }

    # Test if user without write access to a mandatory field can still save
    # record
    {
        foreach my $col ($layout->search_columns(userinput => 1))
        {   $layout->column_update($col, {is_optional => 1}) if $col->name ne 'string1';
        }

        # First check cannot write
        try { $row->cell_update(string1 => '', no_alerts => 1) };
        like $@, qr/is not optional/,
             "Failed to write with permission to mandatory string value";

        $layout->column_update(string1 => { permissions => [ $sheet->group => [] ] });
        try { $row->cell_update(string1 => '', no_alerts => 1) };
        ok !$@, "No error when writing record without permission to mandatory value";

        $layout->column_update(string1 => { permissions => [ $sheet->group => $sheet->default_permissions ] });

        $layout->column_update($_, {is_optional => 0})
            for $layout->search_columns(userinput => 1);
    }

    # Now with filtered value for next page - should wait until page shown
    # Count records now to check nothing written
    my $row_count = $content->row_count;

    foreach my $col ($layout->search_columns(userinput => 1))
    {   if ($col->name eq 'curval1')
        {   $layout->column_update($col, { filter => {
                rules => {
                    column   => 'string1',
                    type     => 'string',
                    value    => '$L1string1',
                    operator => 'equal',
                },
           }});
        }
        else
        {   $layout->column_update($col, { is_optional => 1 });
        }
    }

    my $row2 = $content->row_create({});
    $row2->revision_create({string1 => 'foobar'}, no_alerts => 1);
    like $@, qr/curval1/, "Error for missing curval filtered field value after string write";

    # Test a mandatory field on the second page which the user does not have
    # write access to
    $layout->column_update(curval1 => { permissions => [ $sheet->group => [] ]}, no_alerts => 1);

    cmp_ok $content->row_count, $record_count + 1, "One record written";
}

# Test setting person field as textual value instead of ID
{   my $sheet   = test_sheet '2';
    my $row     = $sheet->content->row_first;

    my $cell0   = $row->cell('person1');
    ok !$cell0->datum, "Person field initially blank";

    # Standard format (surname, forename)
    $row->cell_update($cell0, 'User1 User1', no_alerts => 1);
    my $cell1 = $row->cell('person1');
    isnt $cell1->datum->id, $cell1->datum->id,
        "Person field correctly updated using textual name";

    # Forename then surname, format without a comma
    $row->cell_update('person1', 'User2 User2', no_alerts => 1);
    my $cell2 = $row->cell('person1');
    isnt $cell2->datum->id, $cell1->datum->id,
        "Person field correctly updated using textual name (2)";
}

# Final special test for file with only ID number the same (no new content)
$sheet2 = make_sheet '2',
    data => [ { file1 => undef } ] # This will create default dummy file
);


# 
my $row = $sheet2->content->row_first;
my $old = $row->cell('file1')->datum;
$row->cell_update(file1 => 1);         # Same ID has existing one
my $new = $row->cell('file1')->datum;
is $old->id, $new->id, "Update with same file ID has not changed";

# Test other blank values work whilst we're here
ok ! $row->cell($internal)->is_blank, "internal $internal filled"
    for @{$sheet->layout->internal_columns_show_names};

done_testing;
