use Linkspace::Test;

use Linkspace::Util qw/flat/;

my $data = [
    {
        string1 => 'Foo',
        enum1   => 7,
        enum2   => 10,
        tree1   => 13,
        tree2   => 16,
        curval1 => 1,
        curval2 => 2,
    },
    {
        string1 => 'Bar',
        enum1   => 8,
        enum2   => 11,
        tree1   => 14,
        tree2   => 17,
        curval1 => 1,
        curval2 => 2,
    },
    {
        string1 => 'FooBar',
        enum1   => 9,
        enum2   => 12,
        tree1   => 15,
        tree2   => 18,
        curval1 => 1,
        curval2 => 2,
    },
];

my $curval_sheet = make_sheet 2, multivalues => 1;

my $sheet   = make_sheet 1,
    rows             => $data,
    curval_sheet     => $curval_sheet,
    column_count     => {
        enum   => 2,
        curval => 3, # 2 multi and 1 single (with multi fields)
        tree   => 2,
    },
    multivalue_columns => [ qw/enum curval tree/ ],
    calc_code        => "
        function evaluate (L1enum1, L1curval1, L1tree1)
            values = {}
            for k, v in pairs(L1enum1.values) do table.insert(values, v.value) end
            table.sort(values)
            local text = ''
            for i,v in ipairs(values) do
                text = text .. v
            end
            for i,v in ipairs(L1curval1) do
                text = text .. v.field_values.L2string1[1]
            end
            for i,v in ipairs(L1tree1) do
                text = text .. v.value
            end
            return text
        end
    ",
    calc_return_type => 'string',
);

my @tests = (
    {
        name      => 'Write 2 values',
        write     => {
            enum1   => [7, 8],
            curval1 => [1, 2],
            curval3 => [1],
            tree1   => [13, 14],
        },
        as_string => {
            enum1   => 'foo1, foo2',
            enum2   => 'foo1',
            curval1 => 'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012; Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
            curval2 => 'Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
            curval3 => 'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012',
            tree1   => 'tree1, tree2',
            tree2   => 'tree1',
            calc1   => 'foo1foo2BarFootree1tree2', # 2x enum values then 2x string values from curval then 2x tree
        },
        search    => { column => 'enum1', value  => 'foo2' },
        count     => 2,
    },
    {
        name      => 'Search 2 values',
        write     => {
            enum1  => [7, 8],
            enum2  => [10, 11],
            tree1  => 13,
            tree2  => 16,
        },
        as_string => {
            enum1   => 'foo1, foo2',
            enum2   => 'foo1, foo2',
            curval1 => 'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012; Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
            curval2 => 'Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
            tree1   => 'tree1',
            tree2   => 'tree1',
            calc1   => 'foo1foo2FooBartree1', # 2x enum values then 2x string values from curval, just 1 tree
        },
        search    => [
            { column => 'enum1', value  => 'foo1' },
            { column => 'enum2', value  => 'foo1' },
        ],
        count     => 1,
    },
    {
        name      => 'Search 2 tree values',
        write     => {
            tree1  => [13, 14],
            tree2  => [16, 17],
        },
        as_string => {
            enum1   => 'foo1, foo2',
            enum2   => 'foo1, foo2',
            curval1 => 'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012; Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
            curval2 => 'Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
            tree1   => 'tree1, tree2',
            tree2   => 'tree1, tree2',
            calc1   => 'foo1foo2FooBartree1tree2', # 2x enum values then 2x string values from curval then 2x tree
        },
        search    => [
            { column => 'tree1', value  => 'tree1' },
            { column => 'tree2', value  => 'tree1' },
        ],
        count     => 1,
    },
    {
        name      => 'Search negative 1',
        write     => {
            enum1  => [7, 8],
            enum2  => [11, 12],
        },
        search    => {
            column   => 'enum1',
            operator => 'not_equal',
            value    => 'foo1',
        },
        count     => 2,
    },
    {
        name      => 'Search negative 2',
        write     => {
            enum1  => [7, 8],
            enum2  => [10, 11],
        },
        search    => {
            column   => 'enum1',
            operator => 'not_equal',
            value    => 'foo2',
        },
        count     => 1,
    },
    {
        name      => 'Search negative 3',
        write     => {
            enum1  => [7, 8],
            enum2  => [11, 12],
        },
        search    => {
            column   => 'enum1',
            operator => 'not_equal',
            value    => ['foo1', 'foo2'],
        },
        count     => 1,
    },
    {
        name      => 'Search negative 1 tree',
        write     => {
            tree1  => [13, 14],
            tree2  => [17, 18],
        },
        search    => {
            column   => 'tree1',
            operator => 'not_equal',
            value    => 'tree1',
        },
        count     => 2,
    },
    {
        name      => 'Search negative 2 tree',
        write     => {
            tree1  => [13, 14],
            tree2  => [16, 17],
        },
        search    => {
            column   => 'tree1',
            operator => 'not_equal',
            value    => 'tree2',
        },
        count     => 1,
    },
    {
        name      => 'Search negative 3 tree',
        write     => {
            tree1  => [13, 14],
            tree2  => [17, 18],
        },
        search    => {
            column   => 'tree1',
            operator => 'not_equal',
            value    => ['tree1', 'tree2'],
        },
        count     => 1,
    },
);

foreach my $test (@tests)
{
    my $row1a = $sheet->content->row(3);
    $row1a->cell_update($test->{write});

    # Reload.  Remind that rows are not cached.
    my $row1b = $sheet->content->row(3);

    if(my $as = $test->{as_string})
    {   foreach my $type (keys %$as)
        {   is $row1b->cell($type)->as_string, $as->{$type},
                "$type updated correctly for test $test->{name}";
        }
    }

    my @rules = map +{
        column   => $_->{column},
        type     => 'string',
        value    => $_->{value},
        operator => $_->{operator} || 'equal',
    }, flat $test->{search};

    my $filter = {
        rules     => \@rules,
        condition => 'OR',
    };

    my $view = $sheet->views->view_create({
        name        => 'Test view',
        filter      => $rules,
        columns     => $layout->all_columns,
    );

    my $results = $sheet->content->search({view => $view});
    cmp_ok $results->count, '==', $test->{count},
        "Correct number of records for search $test->{name}";

    my $result = $results->row(1);
    if(my $as = $test->{as_string})
    {   foreach my $type (keys %$as)
        {   is $result->cell($type)->as_string,  $as->{$type},
                "$type updated correctly for test $test->{name}";
        }
    }
}

# Now test that even if a field is set back to single-value, that any existing
# multi-values are still displayed

$layout->column_update($_ => { is_multivalue => 0 })
    for qw/enum1 enum2 curval1 curval2 curval3 tree1 tree2/;

# First test with record retrieved via a content row

my $row1a = $sheet->content->row(3);

my %expected = (
    enum1   => 'foo1, foo2',
    enum2   => 'foo2, foo3',
    curval1 => 'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012; Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
    curval2 => 'Bar, 99, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
    tree1   => 'tree1, tree2',
    tree2   => 'tree2, tree3',
);

foreach my $colname (keys %expected)
{   is $row1a->cell($colname)->as_string, $expected{$colname},
        "$colname correct for single field with multiple values (single retrieval)"; 
}

# And now via a result row

my $row1b = $sheet->content->search->row(1);  # 1 or 3???

foreach my $colname (keys %expected)
{   is $row1b->cell($colname)->as_string, $expected{$colname},
        "$colname correct for single field with multiple values (multiple retrieval)"; 
}

done_testing;
