
use Linkspace::Test;

# Test search of historical values. To make sure that values from other fields
# of the same type are not being included, create 2 fields for each column
# type, setting the initial value as the same to begin with, then only updating
# the first
my @values = (
    {
        field        => 'string',
        begin_set    => 'Foobar1',
        begin_string => 'Foobar1',
        end_set      => 'Foobar2',
        end_string   => 'Foobar2',
        second_field => 'string2',
    },
    # Enum and trees can be set using the text value during initial write only.
    # After that the ID is needed, which is specified by end_set_id (only the
    # first field value is written)
    {
        field        => 'enum',
        begin_set    => 'foo1',
        begin_string => 'foo1',
        end_set      => 'foo2',
        end_set_id   => 8,
        end_string   => 'foo2',
    },
    {
        field        => 'tree',
        begin_set    => 'tree1',
        begin_string => 'tree1',
        end_set      => 'tree2',
        end_set_id   => 14,
        end_string   => 'tree2',
    },
    {
        field        => 'integer',
        begin_set    => 45,
        begin_string => '45',
        end_set      => 55,
        end_string   => '55',
    },
    {
        field        => 'date',
        begin_set    => '2010-01-02',
        begin_string => '2010-01-02',
        end_set      => '2010-03-06',
        end_string   => '2010-03-06',
    },
    {
        field        => 'daterange',
        begin_set    => ['2012-04-02', '2012-05-10'],
        begin_string => '2012-04-02 to 2012-05-10',
        end_set      => ['2012-06-01', '2012-07-10'],
        end_string   => '2012-06-01 to 2012-07-10',
    },
);

my $curval_sheet = make_sheet '2';

my %data1 = map +( $_->{field}.'1' => $_->{begin_set} ), @values;
my %data2 = map +( $_->{field}.'2' => $_->{begin_set} ), @values;
my $sheet = make_sheet '1',
    rows         => [ \%data1, \%data2 ],
    curval_sheet => $curval_sheet,
    column_count => {
        string    => 2,
        enum      => 2,
        tree      => 2,
        integer   => 2,
        date      => 2,
        daterange => 2,
    },
);

my $row1 = $sheet->content->row(1);
my $row2 = $sheet->content->row(2);

# Check initial written values
foreach my $value (@values)
{   my $field1 = $value->{field}.'1';
    is $row1->cell($field1)->as_string, $value->{begin_string},
          "Initial row1 value correct for $field1";

    my $field2 = $value->{field}.'2';
    is $row1->cell($field2)->as_string, $value->{begin_string},
          "Initial row2 value correct for $field2";
}

# Write second values
foreach my $value (@values)
{   my $set_value = $value->{end_set_id} || $value->{end_set};
    $row1->revisions_create({$value->{field}.'1' => $set_value});
}

# Now reload the changed row from the database
my $row1b = Linkspace::Row->from_id($row1->id, sheet => $sheet);

foreach my $value (@values)
{   my $field1 = $value->{field}.'1';
    is $row1->cell($field1)->as_string, $value->{end_string},
        "Written value correct for $value->{field}";
}

foreach my $value (@values)
{
    my $filter1 = { rule  => {
        column   => $value->{field}.'1',
        type     => 'string',
        operator => 'equal',
        value    => $value->{begin_string},
    }};

    my $view1 = $sheet->views->view_create({
        name        => 'Test view',
        filter      => $filter1,
    );

    my $results1 = $sheet->content->search(view => $view1);
    cmp_ok $results->count, '==', 0,
        "No results using normal search on old value - $value->{field}";


    my $filter2 = { rule => {
        column          => $value->{field}.'1',
        type            => 'string',
        operator        => 'equal',
        value           => $value->{begin_string},
        previous_values => 'positive',
    }};

    my $view_previous2 = $sheet->views->view_create({
        name        => 'Test view previous',
        filter      => $filter2,
    );

    my $results2 = $sheet->content->search(view => $view_previous2);
    cmp_ok $results2->count, '==', 1,
        "Returned record when searching previous values - $value->{field}";

}

my @tests = (
    {
        field          => 'integer1',
        value_before   => 340,
        value_after    => 450,
        filter_value   => 420,
        operator       => 'less',
        count_normal   => 0,
        count_previous => 1,
    },
    {
        field          => 'integer1',
        value_before   => 700,
        value_after    => 450,
        filter_value   => 600,
        operator       => 'greater',
        count_normal   => 0,
        count_previous => 1,
    },
    {
        field          => 'integer1',
        value_before   => 340,
        value_after    => 450,
        filter_value   => 340,
        operator       => 'less_or_equal',
        count_normal   => 0,
        count_previous => 1,
    },
    {
        field          => 'integer1',
        value_before   => 340,
        value_after    => 450,
        filter_value   => 340,
        operator       => 'not_equal',
        count_normal   => 1,
        count_previous => 0,
    },
    {
        field          => 'integer1',
        value_before   => undef,
        value_after    => 100,
        operator       => 'is_empty',
        count_normal   => 0,
        count_previous => 1,
    },
    {
        field          => 'integer1',
        value_before   => 100,
        value_after    => undef,
        operator       => 'is_not_empty',
        count_normal   => 0,
        count_previous => 1,
    },
    {
        field          => 'string1',
        value_before   => 'apples',
        value_after    => 'oranges',
        filter_value   => 'apples',
        operator       => 'not_equal',
        count_normal   => 1,
        count_previous => 0,
    },
    {
        field          => 'string1',
        value_before   => 'apples',
        value_after    => 'oranges',
        filter_value   => 'pple',
        operator       => 'contains',
        count_normal   => 0,
        count_previous => 1,
    },
    {
        field          => 'string1',
        value_before   => 'apples',
        value_after    => 'oranges',
        filter_value   => 'pple',
        operator       => 'not_contains',
        count_normal   => 1,
        count_previous => 0,
    },
    {
        field          => 'string1',
        value_before   => 'apples',
        value_after    => 'oranges',
        filter_value   => 'appl',
        operator       => 'not_begins_with',
        count_normal   => 1,
        count_previous => 0,
    },
    {
        field          => 'string1',
        value_before   => undef,
        value_after    => 'Foobar',
        operator       => 'is_empty',
        count_normal   => 0,
        count_previous => 1,
        empty_defined  => 1,
    },
    {
        field          => 'string1',
        value_before   => 'Foobar',
        value_after    => undef,
        operator       => 'is_not_empty',
        count_normal   => 0,
        count_previous => 1,
        empty_defined  => 1,
    },
    {
        field          => 'string1',
        value_before   => undef,
        value_after    => 'Foobar',
        operator       => 'is_empty',
        count_normal   => 0,
        count_previous => 1,
        empty_defined  => 0,
    },
    {
        field          => 'string1',
        value_before   => 'Foobar',
        value_after    => undef,
        operator       => 'is_not_empty',
        count_normal   => 0,
        count_previous => 1,
        empty_defined  => 0,
    },
    {
        field          => 'enum1',
        value_before   => [1,2],
        value_after    => 3,
        filter_value   => 'foo2',
        operator       => 'not_equal',
        count_normal   => 1,
        count_previous => 0,
    },
    {
        # Check other multivalue
        field          => 'enum1',
        value_before   => [1,2],
        value_after    => 3,
        filter_value   => 'foo1',
        operator       => 'not_equal',
        count_normal   => 1,
        count_previous => 0,
    },
);

foreach my $test (@tests)
{
    my $sheet   = make_sheet
        rows        => [ { $test->{field} => $test->{value_before} } ],
        multivalues => 1,
    );

    my $row = $sheet->content->row(1);
    $row->revision_create( { $test->{field} => $test->{value_after}} );

    # Enable tests for both empty string and NULL values
    if (exists $test->{empty_defined})
    {
        my $val = $test->{empty_defined} ? '' : undef;
        $schema->resultset('String')->search({
            value => [undef, ''],
        })->update({
            value       => $val,
            value_index => $val,
        });
    }

    my $filter1 = { rule => {
        column   => $test->{field},
        type     => 'string',
        operator => $test->{operator},
        value    => $test->{filter_value},
    }};

    my $view1 = $sheet->views->view_create({
        name        => 'Test view',
        filter      => $filter1,
    });

    my $results1 = $sheet->content->search(view => $view1);

    cmp_ok $results1->count, '==', $test->{count_normal},
        "Correct number of results - operator $test->{operator}";


    my $filter2 = { rule     => {
        column          => $test->{field},
        type            => 'string',
        value           => $test->{filter_value},
        operator        => $test->{operator},
        previous_values => 'positive',
    } };

    my $view_previous2 = $sheet->views->view_create({
        name        => 'Test view previous',
        filter      => $filter2,
    );

    my $results2 = $sheet->content->search(view => $view_previous2);
    cmp_ok $results2->count, '==', $test->{count_previous},
         "Correct number of results inc previous - operator $test->{operator}";
}

# Test previous values for groups. Make some edits over a period of time, and
# attempt to retrieve previous values only between certain edit dates
{
    set_fixed_time('01/01/2014 01:00:00', '%m/%d/%Y %H:%M:%S');

    my $sheet   = test_sheet
        rows        => [{ integer1 => 10 }],
        multivalues => 1;

    my $row = $content->row(1);

    set_fixed_time('09/01/2014 01:00:00', '%m/%d/%Y %H:%M:%S');
    $row->revision_create({string1 => 'foobar'});

    set_fixed_time('01/02/2015 01:00:00', '%m/%d/%Y %H:%M:%S');
    $row->revision_create({integer1 => 20});

    set_fixed_time('01/01/2016 01:00:00', '%m/%d/%Y %H:%M:%S');
    $row->revision_create({integer1 => 30});

    foreach my $test ('normal', 'inrange', 'outrange')
    {
        foreach my $negative (0..1)
        {
            my $filter = {
                rules     => [
                    {
                        column1         => 'integer1',
                        type            => 'string',
                        operator        => $negative ? 'not_equal' : 'equal',
                        value           => 20,
                    },
                    {
                        column          => '_version_datetime',
                        type            => 'string',
                        operator        => 'greater',
                        value           => $test eq 'inrange' ? '2014-10-01' : '2014-06-01',
                    },
                    {
                        column          => '_version_datetime',
                        type            => 'string',
                        value           => $test eq 'inrange' ? '2015-06-01' : '2014-10-01',
                        operator        => 'less',
                    }
                ],
                operator => 'AND',
            };
            $filter->{previous_values} = 'positive' unless $test eq 'normal';

            my $view_previous = $sheet->views->view_create({
                name        => 'Test view previous group',
                filter      => $filter,
            );

            my $results = $sheet->content->search(view => $view_previous);

            my $expected = $test eq 'inrange' ? 1 : 0;
            $expected = $expected ? 0 : 1
                if $negative && $test ne 'normal';

            cmp_ok $results->count, '==', $expected,
               "Correct number of results for group include previous ($test), negative: $negative";
        }
    }

    # Now a test to see if a value has changed in a certain period
    foreach my $inrange (0..1)
    {
        my $filter = {
            rules     => [
                {
                    rules => [
                        {
                            column          => 'integer1',
                            type            => 'string',
                            operator        => 'equal',
                            value           => 10,
                        },
                        {
                            column          => '_version_datetime',
                            type            => 'string',
                            operator        => 'greater',
                            value           => $inrange ? '2013-06-01' : '2014-10-01',
                        },
                        {
                            column          => '_version_datetime',
                            type            => 'string',
                            operator        => 'less',
                            value           => '2015-06-01',
                        }
                    ],
                    previous_values => 'positive',
                },
                {
                    rules => [
                        {
                            column          => 'integer1',
                            type            => 'string',
                            operator        => 'not_equal',
                            value           => 10,
                        },
                        {
                            column          => '_version_datetime',
                            type            => 'string',
                            operator        => 'greater',
                            value           => $inrange ? '2013-06-01' : '2014-10-01',
                        },
                        {
                            column          => '_version_datetime',
                            type            => 'string',
                            operator        => 'less',
                            value           => '2015-06-01',
                        }
                    ],
                    previous_values => 'positive',
                },
            ],
            operator        => 'AND',
        };

        my $view_previous = $sheet->view_create({
            name        => 'Test view previous group',
            filter      => $rules,
        });

        my $results = $sheet->content->search(view => $view_previous);

        cmp_ok $results->count, '==', ($inrange ? 1 : 0);
            "Correct number of results for group include previous with value change";
    }

    # Negative group previous values match
    foreach my $match (qw/positive negative/) # Check both to ensure difference
    {
        my $filter = { rule => {
            rules => [
                {
                    column          => 'integer1',
                    type            => 'string',
                    operator        => 'equal',
                    value           => 20,
                },
                {
                    column          => '_version_datetime',
                    type            => 'string',
                    operator        => 'less',
                    value           => '2015-06-01',
                },
            ],
            previous_values => $match,
        } };

        my $view_previous = $sheet->views->view_create({
            name        => 'Test view previous group',
            filter      => $filter,
        );

        my $results = $sheet->content->search(view => $view_previous);
        cmp_ok $records->count, '==', ($match eq 'negative' ? 0 : 1),
           "Correct number of results for negative previous value group";
    }

    # Now a test to see if a value has changed in a certain period
    foreach my $inrange (0..1)
    {
        my $filter = { rules     => [
                {
                    rules => [
                        {
                            id              => 'integer1',
                            type            => 'string',
                            operator        => 'equal',
                            value           => 20,
                        },
                        {
                            id              => '_version_datetime',
                            type            => 'string',
                            operator        => 'less',
                            value           => '2014-12-31',
                        }
                    ],
                    previous_values => 'negative',
                },
                {
                    rules => [
                        {
                            column          => 'integer1',
                            type            => 'string',
                            operator        => 'equal',
                            value           => 20,
                        },
                        {
                            column          => '_version_datetime',
                            type            => 'string',
                            operator        => 'greater',
                            value           => '2015-01-01',
                        },
                        {
                            column          => '_version_datetime',
                            type            => 'string',
                            operator        => 'less',
                            value           => '2015-12-31',
                        }
                    ],
                    previous_values => 'positive',
                },
            ],
            operator        => 'AND',
        };

        my $view_previous = $sheet->views->view_create({
            name        => 'Test view previous group',
            filter      => $filter,
        });

        my $results = $sheet->content->search(view => $view_previous);

        cmp_ok $results->count, '==', ($inrange ? 1 : 1)    #XXX
            "Correct number of results for searching for change in period";
    }
}

done_testing;
