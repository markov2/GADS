# Rewrite of t/004_group.t
use Linkspace::Test
    not_ready => 'Doesnt need much more';

foreach my $multivalue (0..1)
{
    # It doesn't make a lot of sense to test a lot of these values, as the grouping
    # of text fields is not really possible (instead, the max value is used).
    # However, add them to the tests, to check that if a user does add them to a
    # grouping view that something unexpected doesn't happen
    my $data = [
        {
            string1    => 'foo1',
            integer1   => 25,
            date1      => '2011-10-10',
            daterange1 => ['2000-01-02', '2001-03-03'],
            enum1      => 8,
            tree1      => 12,
            curval1    => 1,
        },
        {
            string1    => 'foo1',
            integer1   => 50,
            date1      => '2012-10-10',
            daterange1 => ['2004-01-02', '2005-03-03'],
            enum1      => $multivalue ? [7,9] : 7,
            tree1      => 12,
            curval1    => 1,
        },
        {
            string1    => 'foo2',
            integer1   => 60,
            date1      => '2009-10-10',
            daterange1 => ['2007-01-02', '2007-03-03'],
            enum1      => 8,
            tree1      => 11,
            curval1    => 2,
        },
        {
            string1    => 'foo2',
            integer1   => 70,
            date1      => '2008-10-10',
            daterange1 => ['2001-01-02', '2001-03-03'],
            enum1      => 8,
            tree1      => 11,
            curval1    => 2,
        },
    ];

    my $expected = [
        {
            string1    => 'foo1',
            integer1   => 75,
            calc1      => 150,
            date1      => '2 unique',
            daterange1 => '2 unique',
            enum1      => $multivalue ? '3 unique' : '2 unique',
            tree1      => '1 unique',
            curval1    => '1 unique',
        },
        {
            string1    => 'foo2',
            integer1   => 130,
            calc1      => 260,
            date1      => '2 unique',
            daterange1 => '2 unique',
            enum1      => '1 unique',
            tree1      => '1 unique',
            curval1    => '1 unique',
        },
    ];

    my $curval_sheet = make_sheet;

    my $sheet   = make_sheet
        rows           => $data,
        calc_code      => "function evaluate (L1integer1) \n return L1integer1 * 2 \n end",
        curval_sheet   => $curval_sheet,
        curval_columns => [ 'string1' ],
        multivalues    => $multivalue;

    my $layout  = $sheet->layout;

    $layout->column_update($_ => { group_display => 'unique' })
        for grep !$_->numeric, $layout->all_columns;

    my $autocur = $curval_sheet->layout->column_create({
        type            => 'autocur',
        refers_to_sheet => $sheet,
        related_field   => 'curval1',
        curval_columns  => [ 'string1' ],
    });

    my @colnames = qw/string1 integer1 calc1 date1 daterange1 enum1 tree1 curval1/;

    my $view = $sheet->views->view_create({
        name        => 'Group view',
        columns     => \@colnames,
        grouping    => [ 'string1' ],

        # add a sort, to check that doesn't result in unwanted multi-value field joins
        sort_column => 'enum1',
        sort_order  => 'asc',
    });


    my $results = $sheet->content->search(view => $view);
    cmp_ok $results->count, '==', 2, "Correct number of rows for group by string";

    my @expected = @$expected;
    foreach my $row ($results->rows)
    {
        my $expected = shift @expected;
        is $row->cell($_), $expected->{$_}, "... group $_ correct"
            for @colnames;
        is $row->id_count, 2, "ID count correct";  #XXX ?
    }

    # Remove grouped column from view and check still gets added as required
    my $view2 = $sheet->views->view_create({
        name        => 'Group view',
        columns     => [ 'integer1' ],
    });

    my @expected2 = @$expected;
    my $results2 = $sheet->content->search(view => $view2);

    cmp_ok $results2->count, '==', 2, "Correct number of rows for group by string";
    foreach my $row ($results2->rows)
    {   my $expected = shift @expected2;
        is $row->cell($_), $expected->{$_}, "... group $_ correct"
            for qw/string1 integer1/;
    }

    # Test autocur

    $curval_sheet->layout->column_update($autocur => { group_display => 'unique' });
    my $view3 = $curval_sheet->views->view_create({
        name        => 'Group view autocur',
        columns     => [ $autocur->id ],
        grouping    => [ 'string1' ],
    });
    my $results3 = $curval_sheet->content->search(view => $view3);
    cmp_ok $results3->count, '==', 2, "Correct number of rows for group by string with autocur";
    foreach my $row ($results3->rows)
    {   is $row->cell($autocur), '2 unique', "Group text correct";
    }

}

# Make sure that correct columns are returned from view
{
    my $sheet = make_sheet;
    my $view  = $sheet->views->view_create({
        name        => 'Group view',
        columns     => [ 'string1', 'integer1' ],
        grouping    => 'enum1',
    });

    my $results1 = $sheet->content->search({ view => $view });
    my @vids1    = map $_->id, @{$results1->columns_view};
    my @expected1= map $_->id, $sheet->layout->columns( [qw/enum1 integer1/] );
    is "@vids1", "@expected1", "Correct columns in group view";

    my $results2 = $sheet->content->search({
        view               => $view,
        additional_filters => [ { column => 'string1', value => 'Foo' } ],
    });
    my @vids2     = map $_->id, @{$results2->columns_view};
    my @expected2= map $_->id, $sheet->layout->columns( [qw/enum1 string1 integer1/] );
    is "@vids2", "@expected2", "Correct columns in group view";

    $sheet->layout->column_update(string1 => { group_display => 'unique' });
    my $results3 = $sheet->content->search({ view => $view });
    my @vids3     = map $_->id, @{$results3->columns_view};
    my @expected3 = map $_->id, $sheet->layout->columns( [qw/enum1 string1 integer1/] );
    is "@vids3", "@expected3", "Correct columns in group view";
}

# Large number of records (greater than default number of rows in table). Check
# that paging does not affect results
{
    my @data;
    my %group_values;
    for my $count (1..300)
    {   my $id = substr $count, -1;
        push @data, { string1  => "Foo$id", integer1 => $id * 10 };
    }

    my $sheet = make_sheet rows => \@data;

    my $view  = $sheet->views->view_create({
        name        => 'Group view large',
        columns     => [ 'string1', 'integer1' ],
        grouping    => 'string1',
    });

    my $results = $sheet->content->search(
        # Specify rows parameter to simulate default used for table view. This
        # should be ignored
        rows   => 50,
        page   => 1,
        view   => $view,
    );

    cmp_ok $results->count, '==', 10,
        "Correct number of rows for group of large number of records";

    cmp_ok $results->nr_pages, '==', 1,
        "Correct number of pages for large number of records";

    my @expected = (
        { string1  => 'Foo0', integer1 =>    0 },
        { string1  => 'Foo1', integer1 =>  300 },
        { string1  => 'Foo2', integer1 =>  600 },
        { string1  => 'Foo3', integer1 =>  900 },
        { string1  => 'Foo4', integer1 => 1200 },
        { string1  => 'Foo5', integer1 => 1500 },
        { string1  => 'Foo6', integer1 => 1800 },
        { string1  => 'Foo7', integer1 => 2100 },
        { string1  => 'Foo8', integer1 => 2400 },
        { string1  => 'Foo9', integer1 => 2700 },
    );

    foreach my $row ($results->rows)
    {   my $expected = shift @expected;
        is $row->cell('string1'), $expected->{string1}, "Group text correct";
        is $row->cell('integer1'), $expected->{integer1}, "Group integer correct";
        cmp_ok $row->id_count, '==', 30, "ID count correct for large records group";
    }
}

done_testing;
