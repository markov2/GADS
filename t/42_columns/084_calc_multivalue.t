# part 2 of t/007_code.t

use Linkspace::Test;

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

    my $curval_sheet = make_sheet;

    my $sheet        = make_sheet
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

done_testing;
