
use Test::MockTime qw(set_fixed_time restore_time); # Load before DateTime
use Linkspace::Test;

# Fix all tests for this date so that CURDATE is consistent
set_fixed_time('10/10/2014 01:00:00', '%m/%d/%Y %H:%M:%S');

my $long = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum';

my $data = [
    {
        string1    => '',
        integer1   => -4,
        date1      => '',
        daterange1 => ['', ''],
        enum1      => 'foo1',
        tree1      => 'tree1',
        curval1    => 1,
    },{
        string1    => '',
        integer1   => 5,
        date1      => '',
        daterange1 => ['', ''],
        enum1      => 'foo1',
        tree1      => 'tree3',
        curval1    => 2,
    },{
        string1    => '',
        integer1   => 6,
        date1      => '2014-10-10',
        daterange1 => ['2014-03-21', '2015-03-01'],
        enum1      => 'foo1',
        tree1      => 'tree2',
        curval1    => 2,
    },{
        string1    => 'Foo',
        integer1   => 7,
        date1      => '2014-10-10',
        daterange1 => ['2013-10-10', '2013-12-03'],
        enum1      => 'foo1', # Changed to foo2 after creation to have multiple versions
        tree1      => 'tree1',
    },{
        string1    => 'FooBar',
        date1      => '2015-10-10',
        daterange1 => ['2009-01-04', '2017-06-03'],
        enum1      => 'foo2',
        tree1      => 'tree2',
        curval2    => 1,
    },{
        string1    => "${long}1",
        integer1   => 2,
    },{
        string1    => "${long}2",
        integer1   => 3,
    },
];

my $group   = test_group;
my $curval_sheet = make_sheet 2, group => $group;

my $sheet   = test_sheet
    data             => $data,
    curval           => 2,
    multivalue       => 1,
    column_count     => { enum  => 1, curval => 2 },
    calc_return_type => 'date',
    calc_code        => <<'__CALC';
        function evaluate (L1daterange1)
            if type(L1daterange1) == "table" and L1daterange1[1] then
                dr1 = L1daterange1[1]
            elseif type(L1daterange1) == "table" and next(L1daterange1) == nil then
                dr1 = nil
            else
                dr1 = L1daterange1
            end
            if dr1 == nil then return end
            return dr1.from.epoch
        end
__CALC

my $layout  = $sheet->layout;

# Position curval first, as its internal _value fields are more
# likely to cause problems and therefore representative test failures
$layout->reposition( [ qw/curval1 string1 integer1 date1 daterange1 enum1 tree1/ ]);

my $colperms = [ $sheet->group => $sheet->default_permissions ];

$layout->column_create(calc => {
    name        => 'calc_int',
    return_type => 'integer',
    code        => 'function evaluate (L1integer1) return L1integer1 end',
    permissions => $colperms,
});

$curval_layout->column_create(autocur => {
    name            => "$_-xx",
    refers_to_sheet => $sheet,
    related_column  => $layout->column($_),
}) for 'curval1', 'curval2';

$sheet->content->row(6)->cell_update(enum1 => 8);  #XXX 8?

$data->[3]->{enum1} = 'foo2';  #XXX ???

# Add another curval field to a new table
my $curval_sheet2 = make_sheet 3,
    curval_offset    => 12,
    curval_fields    => [ 'integer1' ],
);

my $curval3 = $curval_layout->column_create(curval => {
    name             => 'curval3',
    refers_to_sheet  => $curval_sheet2,
    curval_fields    => [ 'string1' ],
    permissions      => $colperms,
);

my $curval3_value = $curval_sheet2->content->row(1)->current_id;
my $r = $curval_sheet->content->row(1)->cell_update($curval3, $curval3_value);

# Manually force one string to be empty and one to be undef.
# Both should be returned during a search on is_empty
$schema->resultset('String')->find(3)->update({ value => undef });
$schema->resultset('String')->find(4)->update({ value => '' });

{ package Linkspace::Filter::Test;
  use parent 'Linkspace::Filter';
  sub extra { }
}

my @filters = (
    {   name => 'string is Foo',
        rule => {
            column   => 'string1',
            operator => 'equal',
            value    => 'Foo',
        },
        count     => 1,
        aggregate => 7,
    },
    {
        name  => 'check case-insensitive search',
        rule => {
            column   => 'string1',
            operator => 'begins_with',
            value    => 'foo',
        },
        count => 2,
        aggregate => 7,
    },
    {
        name => 'string is long1',
        rule => {
            column   => 'string1',
            operator => 'equal',
            value    => "${long}1",
        },
        count => 1,
        aggregate => 2,
    },
    {
        name => 'string is long',
        rule => {
            column   => 'string1',
            operator => 'begins_with',
            value    => $long,
        },
        count => 2,
        aggregate => 5,
    },
    {
        name => 'date is equal',
        rule => {
            column   => 'date1',
            operator => 'equal',
            value    => '2014-10-10',
        },
        count => 2,
        aggregate => 13,
    },
    {
        name  => 'date using CURDATE',
        rule => {
            column   => 'date1',
            operator => 'equal',
            value    => 'CURDATE',
        },
        count => 2,
        aggregate => 13,
    },
    {
        name => 'date using CURDATE plus 1 year',
        rule => {
            column   => 'date1',
            operator => 'equal',
            value    => 'CURDATE + '.(86400 * 365), # close enough
        },
        count => 1,
        aggregate => '',
    },
    {
        name => 'date in calc',
        rule => {
            column   => 'calc1',
            type     => 'date',   # = return_type in filter
            operator => 'equal',
            value    => 'CURDATE - '.(86400 * 365), # close enough
        },
        count => 1,
        aggregate => 7,
    },
    {
        name  => 'negative filter for calc',
        rule => {
            column   => $calc_int,
            type     => 'string',
            operator => 'less',
            value    => -1,
        },
        count => 1,
        aggregate => -4,
    },
    {
        name => 'date is empty',
        rule => {
            column   => 'data1',
            operator => 'is_empty',
        },
        count => 4,
        aggregate => 6,
    },
    {
        name  => 'date is empty - value as array ref',
        rule => {
            column   => 'date1',
            operator => 'is_empty',
            value    => [],
        },
        count => 4,
        aggregate => 6,
    },
    {
        name => 'date is blank string', # Treat as empty
        rule => {
            column   => 'date1',
            operator => 'equal',
            value    => '',
        },
        count     => 4,
        no_errors => 1, # Would normally bork
        aggregate => 6,
    },
    {
        name => 'string begins with Foo',
        rule => {
            column   => 'string1',
            operator => 'begins_with',
            value    => 'Foo',
        },
        count => 2,
        aggregate => 7,
    },
    {
        name => 'string contains ooba',
        rule => {
            column   => 'string1',
            operator => 'contains',
            value    => 'ooba',
        },
        count => 1,
        aggregate => '',
    },
    {
        name => 'string does not contain ooba',
        rule => {
            column   => 'string1',
            operator => 'not_contains',
            value    => 'ooba',
        },
        count => 6,
        aggregate => 19,
    },
    {
        name => 'string does not begin with Foo',
        rule => {
            column   => 'string1',
            operator => 'not_begins_with',
            value    => 'Foo',
        },
        count => 5,
        aggregate => 12,
    },
    {
        name => 'string is empty',
        rule => {
            column   => 'string1',
            operator => 'is_empty',
        },
        count => 3,
        aggregate => 7,
    },
    {
        name => 'string is not equal to Foo',
        rules=> {
            column   => 'string1',
            operator => 'not_equal',
            value    => 'Foo',
        },
        count => 6,
        aggregate => 12,
    },
    {
        name => 'string is not equal to nothing', # should convert to not empty
        rule => {
            column   => 'string1',
            operator => 'not_equal',
            value    => '',
        },
        count => 4,
        aggregate => 12,
    },
    {
        name => 'string is not equal to nothing (array ref)', # should convert to not empty
        rule => {
            column   => 'string1',
            operator => 'not_equal',
            value    => [],
        },
        count => 4,
        aggregate => 12,
    },
    {
        name => 'greater than undefined value', # matches against empty instead
        rule => {
            column   => 'integer1',
            operator => 'greater',
        },
        count => 1,
        aggregate => '',
    },
    {
        name => 'negative integer filter',
        rule => {
            column   => 'integer1',
            operator => 'less',
            value    => -1,
        },
        count => 1,
        aggregate => -4,
    },
    {
        name => 'daterange less than',
        rule => {
            column   => 'daterange1',
            operator => 'less',
            value    => '2013-12-31',
        },
        count => 1,
        aggregate => 7,
    },
    {
        name => 'daterange less or equal',
        rule => {
            column   => 'daterange1',
            operator => 'less_or_equal',
            value    => '2013-12-31',
        },
        count => 2,
        aggregate => 7,
    },
    {
        name => 'daterange greater than',
        rule => {
            column   => 'daterange1',
            operator => 'greater',
            value    => '2013-12-31',
        },
        count => 1,
        aggregate => 6,
    },
    {
        name => 'daterange greater or equal',
        rule => {
            column   => 'daterange1',
            value    => '2014-10-10',
            operator => 'greater_or_equal',
        },
        count => 2,
        aggregate => 6,
    },
    {
        name => 'daterange equal',
        rule => {
            column   => 'daterange1',
            operator => 'equal',
            value    => '2014-03-21 to 2015-03-01',
        },
        count => 1,
        aggregate => 6,
    },
    {
        name => 'daterange not equal',
        rule => {
            column   => 'daterange1',
            operator => 'not_equal',
            value    => '2014-03-21 to 2015-03-01',
        },
        count => 6,
        aggregate => 13,
    },
    {
        name => 'daterange empty',
        rule => {
            column   => 'daterange1',
            operator => 'is_empty',
        },
        count => 4,
        aggregate => 6,
    },
    {
        name => 'daterange not empty',
        rule => {
            column   => 'daterange1',
            operator => 'is_not_empty',
        },
        count => 3,
        aggregate => 13,
    },
    {
        name => 'daterange contains',
        rule => {
            column   => 'daterange1',
            operator => 'contains',
            value    => '2014-10-10',
        },
        count => 2,
        aggregate => 6,
    },
    {
        name => 'daterange does not contain',
        rule => {
            column   => 'daterange1',
            operator => 'not_contains',
            value    => '2014-10-10',
        },
        count => 5,
        aggregate => 13,
    },
    {
        name  => 'nested search',
        rules => [{
            column   => 'string1',
            operator => 'begins_with',
            value    => 'Foo',
        }, {
            rules => [ {
                column   => 'date1',
                operator => 'equal',
                value    => '2015-10-10',
            }, {
                column   => 'date1',
                operator => 'greater',
                value    => '2014-12-01',
            } ],
        } ],
        condition => 'AND',
        count     => 1,
        aggregate => '',
    },
    {
        name => 'Search using enum with different tree in view',
        rule => {
            column   => 'enum1',
            operator => 'equal',
            value    => 'foo1',
        },
        count => 3,
        aggregate => 7,
    },
    {
        name => 'Search negative multivalue enum',
        rule => {
            column   => 'enum1',
            operator => 'not_equal',
            value    => 'foo1',
        },
        count => 4,
        aggregate => 12,
    },
    {
        name    => 'Search using enum with curval in view',
        columns => [ 'curval1' ],
        rule    => {
            column   => 'enum1',
            operator => 'equal',
            value    => 'foo1',
        },
        count => 3,
        values => {
            curval1 => "Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012",
        },
        aggregate => 7,
    },
    {
        name    => 'Search 2 using enum with different tree in view',
        columns => [ 'tree1', 'enum1' ],
        rule    => {
            column   => 'tree1',
            operator => 'equal',
            value    => 'tree1',
        },
        count => 2,
        aggregate => 3,
    },
    {
        name    => 'Search for ID',
        columns => [ 'string1' ],
        rule    => {
            column   => '_id',
            operator => 'equal',
            value    => '4',
        },
        count => 1,
        aggregate => 5,
    },
    {
        name    => 'Search for multiple IDs',
        columns => [ 'string1' ],
        rule    => {
            column   => '_id',
            operator => 'equal',
            value    => ['4', '5'],
        },
        count => 2,
        aggregate => 11,
    },
    {
        name    => 'Search for empty IDs',
        columns => [ 'string1' ],
        rule    => {
            column   => '_id',
            operator => 'equal',
            value    => [],
        },
        count => 0,
        aggregate => '',
    },
    {
        name    => 'Search for version date 1',
        columns => [ 'string1' ],
        rules   => [{
            column   => '_version_datetime',
            operator => 'greater',
            value    => '2014-10-10',
        }, {
            column   => '_version_datetime',
            operator => 'less',
            value    => '2014-10-11',
        } ],
        condition => 'AND',
        count     => 7,
        aggregate => 19,
    },
    {
        name    => 'Search for version date 2',
        columns => [ 'string1' ],
        rule    => {
            column   => '_version_datetime',
            operator => 'greater',
            value    => '2014-10-15',
        },
        count => 0,
        aggregate => '',
    },
    {
        name    => 'Search for created date',
        columns => [ 'string1' ],
        rule    => {
            column   => '_created',
            operator => 'less',
            value    => '2014-10-15',
        },
        count => 7,
        aggregate => 19,
    },
    {
        name    => 'Search for version editor',
        columns => [ 'string1' ],
        rule    => {
            column   => '_version_user',
            operator => 'equal',
            value    => $user->value,
        },
        count     => 1, # Other records written by superadmin user on start
        aggregate => 7,
    },
    {
        name    => 'Search for invalid date',
        columns => [ 'string1' ],
        rule    => {
            column   => 'date1',
            operator => 'equal',
            value    => '20188-01',
        },
        count     => 0,
        no_errors => 1,
        aggregate => '',
    },
    {
        name    => 'Search for invalid daterange',
        columns => [ 'string1' ],
        rule    => {
            column   => 'daterange1',
            operator => 'equal',
            value    => '20188-01 XX',
        },
        count     => 0,
        no_errors => 1,
        aggregate => '',
    },
    {
        name => 'Search for blank calc date as empty string (array ref)',
        rule => {
            column   => 'calc1',
            type     => 'date',
            operator => 'equal',
            value    => [''],
        },
        count     => 4,
        aggregate => 6,
    },
    {
        name    => 'Search by curval ID',
        columns => [ 'string1' ],
        rule    => {
            column   => 'curval1',
            type     => 'string',
            operator => 'equal',
            value    => '2',
        },
        count     => 2,
        aggregate => 11,
    },
    {
        name    => 'Search by curval ID not equal',
        columns => [ 'string1' ],
        rule    => {
            column   => 'curval1',
            type     => 'string',
            operator => 'not_equal',
            value    => '2',
        },
        count     => 5,
        aggregate => 8,
    },
    {
        name  => 'Search curval ID and enum, only curval in view',
        columns => [ 'curval1' ], # Ensure it's added as first join
        rules   => [ {
            column   => 'curval1',
            type     => 'string',
            operator => 'equal',
            value    => '1',
        }, {
            column   => 'enum1',
            operator => 'equal',
            value    => 'foo1',
        }],
        condition => 'AND',
        count     => 1,
        aggregate => -4,
    },
    {
        name    => 'Search by curval field',
        columns => [ 'string1' ],
        rule    => {
            column   => [ curval1 => $curval_layout->column('string1') ],
            operator => 'equal',
            value    => 'Bar',
        },
        count     => 2,
        aggregate => 11,
    },
    {
        name    => 'Search by curval field not equal',
        columns => [ 'string1' ],
        rules   => {
            column   => [ curval1 => $curval_layout->column('string1') ],
            operator => 'not_equal',
            value    => 'Bar',
        },
        count     => 5,
        aggregate => 8,
    },
    {
        name    => 'Search by curval enum field',
        columns => [ 'enum1' ],
        rule    => {
            column   => [ curval1 => $curval_layout->column('enum1') ],
            operator => 'equal',
            value    => 'foo2',
        },
        count     => 2,
        aggregate => 11,
    },
    {
        name    => 'Search by curval within curval',
        columns => [ 'curval1' ],
        rule    => {
            column   => [ curval1 => $curval3 ],
            type     => 'string',
            operator => 'equal',
            value    => $curval3_value,
        },
        count     => 1,
        aggregate => -4,
    },
    {
        name    => 'Search by curval enum field across 2 curvals',
        columns => [ 'enum1' ],
        rules   => [ {
            column   => [ curval1 => $curval_layout->column('enum1') ],
            value    => 'foo2',
            operator => 'equal',
        }, {
            column   => [ curval2 => $curval_layout->column('enum1') ],
            value    => 'foo1',
            operator => 'equal',
        } ],
        condition => 'OR',
        count     => 3,
        aggregate => 11,
    },
    {
        name    => 'Search by autocur ID',
        columns => [ 'autocur1' ],
        rule    => {
            column   => 'autocur1',
            type     => 'string',
            value    => '3',
            operator => 'equal',
        },
        count     => 1,
        layout    => $curval_layout,
        aggregate => 50,
    },
    {
        name    => 'Search by autocur ID not equal',
        columns => [ 'autocur1' ],
        rule    => {
            column   => 'autocur1',
            type     => 'string',
            operator => 'not_equal',
            value    => '3',
        } ],
        count       => 1,
        # Autocur treated as a multivalue with a single row with 2 different
        # values that are counted separately on a graph
        count_graph => 2,
        layout      => $curval_layout,
        aggregate   => 99,
    },
    {
        name    => 'Search by autocur enum field',
        columns => [ 'string1' ],
        rule    => {
            column   => [ autocur1 => $layout->column('enum1') ],
            type     => 'string',
            value    => 'foo1',
            operator => 'equal',
        } ],
        count     => 2,
        layout    => $curval_layout,
        aggregate => 149,
    },
    {
        name    => 'Search for invalid autocur',
        columns => [ 'autocur1' ],
        rule    => {
            column   => 'autocur1',
            type     => 'string',
            operator => 'equal',
            value    => 'Foobar',
        } ],
        count     => 0,
        no_errors => 1,
        layout    => $curval_layout,
        aggregate => '',
    },
    {
        name    => 'Search by record ID',
        columns => [ 'string1' ],
        rule    => {
            column   => 'ID',
            operator => 'equal',
            value    => '3',
        },
        count     => 1,
        aggregate => -4,
    },
    {
        name    => 'Search by invalid record ID',
        columns => [ 'string1' ],
        rule    => {
            column   => 'ID',
            operator => 'equal',
            value    => '3DD',
        },
        count     => 0,
        no_errors => 1,
        aggregate => '',
    },
);

foreach my $multivalue (0..1)
{   $sheet->set_multivalue($multivalue);

    # Set aggregate fields. Only needs to be done once, and after that the user
    # does not have permission to write the field settings
    my $integer1        = $layout->column('integer1');
    my $integer1_curval = $curval_layout->column('integer1');

    if(!$multivalue)
    {   $integer1->column_update(aggregate => 'sum');
        $integer1_curval->column_update(aggregate => 'sum');
    }

  FILTER:
    foreach my $filter (@filters)
    {   my $layout_filter = $filter->{layout};
        my $sheet = ($layout_filter || $layout)->sheet;

        my $view = try { $sheet->views->view_create({
            name      => 'Test view',
            filter    => {
                rules     => $filter->{rules} || $filter->{rule},
                condition => $filter->{condition},
            },
            columns   => $filter->{columns} || [ qw/string1 tree1/ ],
        }) };

        # If the filter is expected to bork, then check that it actually does first
        if($filter->{no_errors})
        {   ok $@, "Failed to write view with invalid value, test: $filter->{name}";
            is $@->wasFatal->reason, 'ERROR',
                 "Generated user error when writing view with invalid value";
            next FILTER;
        }

        my $page = $sheet->content->search(view => $view);

        cmp_ok $records->count, '==', $filter->{count},
             "$filter->{name} for record count()";

        cmp_ok scalar @{$records->results}, '==', $filter->{count},
             "$filter->{name} actual number records";

        if(my $tv = $filter->{values})
        {   my $row = $page->row(1);
            foreach my $field (keys %$tc)
            {   is $row->cell($field)->as_string, $tv->{$field}, ".. test value $field";
            }
        }

        $sheet->views->view_update($view, { sortings => [ [$view_columns, ['asc']] ]});
        my $page = $sheet->content->search(view => $view);

        cmp_ok $records->count, '==', $filter->{count},
            "$filter->{name} for record count()";

        cmp_ok scalar @{$records->results}, '==', $filter->{count},
            "$filter->{name} actual number records";

        # Basic aggregate tests
        {   my @column_ids = @{$view->columns};
            my $int_id = $records->sheet_id == $curval_sheet->id
                ? $integer1_curval->id : $integer1->id;

            push @column_ids, $int_id if ! grep $_ == $int_id, @column_ids;
            $sheet->views->view_update({columns => \@column_ids});

            my $aggregate = $page->aggregate_results;
            is $aggregate->cell($int_id)->as_string, $filter->{aggregate},
                "Aggregate integer value correct";
        }

        # Basic graph test. Total of points on graph should match the number of results
        my $axis = $filter->{columns}->[0] || $layout->column('string1')->id;
        my $graph = $sheet->graphs->graph_create({
            title => 'Test',
            type => 'bar',
            x_axis => $axis,
            y_axis => $axis,
            y_axis_stack => 'count',
        });

        my $graph_data = GADS::Graph::Data->new(
            id      => $graph->id,
            view    => $view,
            records => $records_group,
        );

        # Count total number of records
        my $graph_total = sum map scalar($_), @{$graph_data->points->[0]};
        my $count = $filter->{count_graph} || $filter->{count};

        cmp_ok $graph_total, '==', $count,
            "Item total on graph matches table for $filter->{name}";
    }
}

foreach my $multivalue (0..1)
{
    $sheet->set_multivalue($multivalue);

    my $view_limit = $sheet->views->view_create({
        name        => 'Limit to view',
        filter      => { rule  => {
            column   => 'date1',
            type     => 'date',
            value    => '2014-10-10',
            operator => 'equal',
        }},
        is_for_admins => 1,
    });

    $user->set_view_limits( [$view_limit] );

    my $view = $sheet->views->view_create({
        name        => 'Foo',
        filter      => { rule => {
            column   => 'string1',
            type     => 'string',
            value    => 'Foo',
            operator => 'begins_with',
        }},
    });

    my $content = $sheet->content;
    my $page = $content->search(view => $view);

    cmp_ok $page->count, '==', 1, 'Correct number of results when limiting to a view';

    # Check can only directly access correct records. Test with and without any
    # columns selected.
    for (0..1)
    {
        my $cols_select = $_ ? [] : undef;
        is $content->row(5, columns => $cols_select)->current_id, 5,
            "Retrieved viewable current ID 5 in limited view";

        is $content->row(5, columns => $cols_select)->current_id, 5,
            "Retrieved viewable record ID 5 in limited view";

        try { $content->row(4) };
        ok( $@, "Failed to retrieve non-viewable current ID 4 in limited view" );

        try { $content->row(4) };
        ok( $@, "Failed to retrieve non-viewable record ID 4 in limited view" );

        # Temporarily flag record as deleted and check it can't be shown
        $schema->resultset('Current')->find(5)->update({ deleted => DateTime->now });

        try { $content->row(5) };
        like $@, qr/Requested record not found/, "Failed to find deleted current ID 5";

        try { $content->row(5) };
        like $@, qr/Requested record not found/, "Failed to find deleted record ID 5";

        # Draft record whilst view limit in force
        my $draft = $content->draft_create({ cells => [ string1 => 'Draft' ] });
        $draft->load_remembered_values;

        is $draft->field('string1')->as_string, "Draft", "Draft sub-record retrieved";

        # Reset
        $content->cell_update(5, { is_deleted => 0 });
    }

    my $view_limit2 = $sheet->views->create_view({
        name        => 'Limit to view2',
        filter      => { rule => {
            columns  => 'date1',
            type     => 'date',
            value    => '2015-10-10',
            operator => 'equal',
        }},
    });

    $user->set_view_limits( [$view_limit, $view_limit2] );

    my $page = $sheet->search(view => $view);
    cmp_ok $records->count, '==', 2, 'Correct number of results when limiting to 2 views';

    # view limit with a view with negative match multivalue filter
    # (this has caused recusion in the past)
    {
        # First define limit view
        my $view_limit3 = $sheet->views->create_view({
            name        => 'limit to view',
            filter      => { rule => {
                column   => 'enum1',
                type     => 'string',
                operator => 'not_equal',
                value    => 'foo1',
            }},
        });
        $user->set_view_limits([ $view_limit3 ]);

        # Then add a normal view
        my $view = $sheet->views->create_view({
            name        => 'date1',
            filter      => { rule => {
                column   => 'date1',
                type     => 'string',
                operator => 'equal',
                value    => '2014-10-10',
            }},
        );
        my $page = $sheet->search(view => $view);

        cmp_ok $page->number_rows, '==', 1,
            'Correct result count when limiting to negative multivalue view';

        cmp_ok scalar @{$page->rows}, '==', 1,
            'Correct number of results when limiting to negative multivalue view';
    }

    # Quick searches
    # Limited view still defined
    my $page1 = $content->search('Foobar');
    cmp_ok $page1->row_count, '==', 0,
        'quick search results when limiting to a view';

    # And again with numerical search (also searches record IDs). Current ID in limited view
    my $page2 = $content->search(8);
    cmp_ok $page2->row_count, '==', 1,
        'quick search results for number when limiting to a view (match)';

    # This time a current ID that is not in limited view
    my $page3 = $records->search(5);
    cmp_ok $page3->row_count, '==', 0,
        'quick search results for number when limiting to a view (no match)';

    # Reset and do again with non-negative view
    $user->set_view_limits([$view_limit]);
    my $page4 = $content->search('Foobar');
    cmp_ok $page4->row_count, '==', 0,
        'quick search results when limiting to a view';

    # Current ID in limited view
    my $page5 = $content->search(8);
    cmp_ok $page5->row_count, '==', 0,
        'quick search results for number when limiting to a view (match)';

    # Current ID that is not in limited view
    my $page6 = $content->search(5);
    cmp_ok $page6->row_count, '==', 1,
        'quick search results for number when limiting to a view (no match)';

    # Same again but limited by enumval
    $views->view_update($view_limit, {
        filter => { rule => {
            columnn  => 'enum1',
            type     => 'string',
            value    => 'foo2',
            operator => 'equal',
        }},
    });

#XXX install $view_limit?
    my $page7 = $content->search;
    cmp_ok $page7->row_count, '==', 2, 'limiting to a view with enumval';

    $user->view_limit($view_limit);   # add?
    ok $page7->row_by_current_id(7), "Retrieved record within limited view";

    $views->view_delete($view_limit);

    my $page = $content->search('2014-10-10');
    cmp_ok $page->row_count, '==', 1,
        'quick search results when limiting to a view with enumval';

    # Check that record can be retrieved for edit
    my $record = layout->edit(...,
        user                 => $user,
        layout               => $layout,
        curcommon_all_fields => 1, # Used for edits
    );
    $record->find_current_id($records->single->current_id);

    # Same again but limited by curval
    $view_limit->filter({ rule     => {
            column   => 'curval1',
            type     => 'string',
            operator => 'equal',
            value    => '1',
        },
    });

    $records = GADS::Records->new(
        view_limits => [ $view_limit ],
        user    => $user,
        layout  => $layout,
    );
    is ($records->count, 1, 'Correct number of results when limiting to a view with curval');
    is (@{$records->results}, 1, 'Correct number of results when limiting to a view with curval');

    # Check that record can be retrieved for edit
    my $page11 = $sheet->search({
        curcommon_all_fields => 1, # Used for edits
    });
    $record->find_current_id($records->single->current_id);

    {   $user->add_viewlimit($view_limit);
        ok $page11->row_by_current_id(3), "Retrieved record within limited view";
        $limit->delete;
    }

    $records->search('foo1');
    is (@{$records->results}, 1, 'Correct number of quick search results when limiting to a view with curval');

    # Now normal
    $user->set_view_limits([]);
    $records = GADS::Records->new(
        user    => $user,
        layout  => $layout,
    );
    $records->clear;
    $records->search('2014-10-10');
    is (@{$records->results}, 4, 'Quick search for 2014-10-10');
    $records->clear;
    $records->search('Foo');
    is (@{$records->results}, 3, 'Quick search for foo');
    $records->clear;
    $records->search('Foo*');
    is (@{$records->results}, 5, 'Quick search for foo*');
    $records->clear;
    $records->search('99');
    is (@{$records->results}, 2, 'Quick search for 99');
    $records->clear;
    $records->search('1979-01-204');
    is (@{$records->results}, 0, 'Quick search for invalid date');

    # Specific record retrieval
    $record = GADS::Record->new(
        user   => $user,
        layout => $layout,
    );
    is( $record->find_record_id(3)->record_id, 3, "Retrieved history record ID 3" );
    $record->clear;
    is( $record->find_current_id(3)->current_id, 3, "Retrieved current ID 3" );
    # Find records from different layout
    $record->clear;
    is( $record->find_record_id(1)->record_id, 1, "Retrieved history record ID 1 from other datasheet" );
    $record->clear;
    is( $record->find_current_id(1)->current_id, 1, "Retrieved current ID 1 from other datasheet" );
    # Records that don't exist
    $record->clear;
    try { $record->find_record_id(100) };
    like( $@, qr/Record version ID 100 not found/, "Correct error when finding record version that does not exist" );
    $record->clear;
    try { $record->find_current_id(100) };
    like( $@, qr/Record ID 100 not found/, "Correct error when finding record ID that does not exist" );
    try { $record->find_current_id('XYXY') };
    like( $@, qr/Invalid record ID/, "Correct error when finding record ID that is invalid" );
    try { $record->find_current_id('123XYXY') };
    like( $@, qr/Invalid record ID/, "Correct error when finding record ID that is invalid (2)" );
}

{
    # Test view_limit_extra functionality
    my $sheet = t::lib::DataSheet->new(data =>
    [ { string1 => 'FooBar', integer1   =>  50 },
      { string1 => 'Bar',    integer1   => 100 },
      { string1 => 'Foo',    integer1   => 150 },
      { string1 => 'FooBar', integer1   => 200 },
    ]);

    my $limit_extra1 = $sheet->views->view_create({
        name    => 'Limit to view extra',
        filter  => {
            rule  => {
                column   => 'string1',
                operator => 'equal',
                value    => 'FooBar',
            },
        },
    });

    my $limit_extra2 = $sheet->views->view_create({
        name        => 'Limit to view extra',
        filter      => {
            rule     => {
                column1  => 'integer1',
                type     => 'string',     #XXX sure?
                operator => 'greater',
                value    => '75',
            },
        },
    });

    $sites->document->sheet_update($sheet, { default_view_limit_extra => $limit_extra1 });

    my $page0 = $sheet->content->search;
    cmp_ok $page0->row_count, '==', 2, '... rows limited to a view limit extra';
    $page0->row(1)->cell('string1')->as_string, 'FooBar', '... limited record';

    my $page1 = $sheet->content->search({ view_limit_extra => $limit_extra2 });
    ok $page1, 'Applied second view limit in search';

    cmp_ok $page1->row_count, '==', 3,
        '... number of results when changing view limit extra';

    $page1->row(1)->cell($string1)->as_string, 'Bar',
        '... limited record when changed';


    $site->users->user_update($user, { view_limits => [ $limit_extra1 ]});

    my $page2 = $sheet->content->search({ view_limit_extra => $limit_extra2 });
    ok $page2, 'Applied second view limit in search, with default limit as well';

    cmp_ok $page2->row_count, '==', 1, '... rows with both view limits and extra limits';
    $page2->row(1)->cell('string1')->as_string, 'FooBar',
       "... limited record for both types of limit";
}

# Check sorting functionality

{   # First check default_sort functionality

    # ASC
    $sheet->sheet_update({sort_column => $layout->column('_id'), sort_type => 'asc'});
    my $page1 = $sheet->content->search;
    is $page1->row(0)->current_id, 3, "Correct first record for default_sort (asc)";
    is $page1->row(-1)->current_id, 9, "Correct last record for default_sort (asc)";

    # DESC
    $sheet->sheet_update({sort_column => $layout->column('_id'), sort_type => 'desc'});
    my $page2 = $sheet->content->search;
    is $page2->row(0)->current_id, 9, "Correct first record for default_sort (desc)";
    is $page2->row(-1)->current_id, 3, "Correct last record for default_sort (desc)";

    # Column from view
    $sheet->sheet_update({sort_column => $layout->column('integer1'), sort_type => 'asc'});
    my $page3 = $sheet->content->search;
    is $page3->row(0)->current_id, 6, "Correct first record for default_sort (column in view)";
    is $page3->row(-1)->current_id, 7, "Correct last record for default_sort (column in view)";

    # Standard sort parameter for search()
    my $page4 = $sheet->content->search(
        sort => { type => 'desc', id   => $layout->column('integer1')->id },
    );
    is $page4->row(0)->current_id, 6, "Correct first record for standard sort";
    is $page4->row(-1)->current_id, 7, "Correct last record for standard sort";

    # Standard sort parameter for search() with invalid column. This can happen if the
    # user switches tables and there is still a sort parameter in the session. In this
    # case, it should revert to the default search.
    $sheet->sheet_update({sort_column => $layout->column('integer1'), sort_type => 'desc' });
    my $page5 = $sheet->content->search(sort => { type => 'desc', id => -1000 });
    is $page5->row(0)->current_id, 6, "Correct first record for standard sort";
    is $page5->row(-1)->current_id, 7, "Correct last record for standard sort";
}

my @sorts = (
    {
        name         => 'Sort by ID descending',
        show_columns => [qw/string1 enum1/],
        sort_by      => [undef],
        sort_type    => ['desc'],
        first        => qr/^9$/,
        last         => qr/^3$/,
    },
    {
        name         => 'Sort by single column in view ascending',
        show_columns => [qw/string1 enum1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['asc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(6|7)$/,
    },
    {
        name         => 'Sort by single column not in view ascending',
        show_columns => [qw/string1 tree1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['asc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(6|7)$/,
    },
    {
        name         => 'Sort by single column not in view descending',
        show_columns => [qw/string1 tree1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['desc'],
        first        => qr/^(6|7)$/,
        last         => qr/^(8|9)$/,
    },
    {
        name         => 'Sort by single column not in view ascending (opposite enum columns)',
        show_columns => [qw/string1 enum1/],
        sort_by      => [qw/tree1/],
        sort_type    => ['asc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(4)$/,
    },
    {
        name         => 'Sort by two columns, one in view one not in view, asc then desc',
        show_columns => [qw/string1 tree1/],
        sort_by      => [qw/enum1 daterange1/],
        sort_type    => ['asc', 'desc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(7)$/,
    },
    {
        name         => 'Sort with filter on enums',
        show_columns => [qw/enum1 curval1 tree1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['asc'],
        first        => qr/^(3)$/,
        first_string => { curval1 => '' },
        last         => qr/^(6)$/,
        last_string  => { curval1 => 'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012' },
        max_id       => 6,
        min_id       => 3,
        count        => 2,
        filter       => {
            rule => {
                column   => 'tree1',
                value    => 'tree1',
                operator => 'equal',
            },
        },
    },
    # Sometimes _value table numbers can get mixed up, so try the opposite way round as well
    {
        name         => 'Sort with filter on enums - opposite filter/sort combo',
        show_columns => [qw/enum1 curval1 tree1/],
        sort_by      => [qw/tree1/],
        sort_type    => ['asc'],
        first        => qr/^(3)$/,
        last         => qr/^(4)$/,
        max_id       => 5,
        min_id       => 3,
        count        => 3,
        filter       => {
            rule => {
                column   => 'enum1',
                operator => 'equal',
                value    => 'foo1',
            },
        },
    },
    {
        name         => 'Sort by enum that is after another enum in the fetched column',
        show_columns => [qw/enum1 curval1 tree1/],
        sort_by      => [qw/tree1/],
        sort_type    => ['asc'],
        first        => qr/^(8|9)$/,
        last         => qr/^(4)$/,
    },
    {
        name         => 'Sort by enum with filter on curval',
        show_columns => [qw/enum1 curval1 tree1/],
        sort_by      => [qw/enum1/],
        sort_type    => ['asc'],
        first        => qr/^(4|5)$/,
        last         => qr/^(7)$/,
        max_id       => 7,
        min_id       => 4,
        count        => 3,
        filter       => {
            rules => [ {
                column   => [ 'curval1', $curval_layout->column('enum1') ],
                operator => 'equal',
                value    => 'foo2',
            }, {
                column   => [ 'curval2', $curval_layout->column('enum1') ],
                operator => 'equal',
                value    => 'foo1',
            } ],
            condition => 'OR',
        },
    },
    {
        name         => 'Sort by curval with filter on curval',
        show_columns => [ qw/enum1 curval1 curval2/ ],
        sort_by      => [ qw/curval1/ ],
        sort_type    => ['asc'],
        first        => qr/^(4|5)$/,
        last         => qr/^(3)$/,
        max_id       => 5,
        min_id       => 3,
        count        => 3,
        filter       => {
            rules => [ {
                column   => [ 'curval1', $curval_layout->column('enum1') ],
                type     => 'string',
                value    => 'foo1',
                operator => 'equal',
            }, {
                column   => [ 'curval1', $curval_layout->column('enum1') ],
                type     => 'string',
                value    => 'foo2',
                operator => 'equal',
            } ],
            condition => 'OR',
        },
    },
    {
        name           => 'Sort by field in curval',
        show_columns   => [qw/enum1 curval1 curval2/],
        sort_by        => [qw/string1/],
        sort_by_parent => [qw/curval1/],
        sort_type      => ['asc'],
        first          => qr/^(6|7|8|9)$/,
        last           => qr/^(3)$/,
        max_id         => 9,
        min_id         => 3,
        count          => 7,
    },
    {
        name         => 'Sort by curval without curval in view',
        show_columns => [qw/string1/],
        sort_by      => [qw/curval1/],
        sort_type    => ['asc'],
        first        => qr/^(6|7|8|9)$/,
        last         => qr/^(3)$/,
        max_id       => 9,
        min_id       => 3,
        count        => 7,
    },
    {
        name           => 'Sort by field in curval without curval in view',
        show_columns   => [qw/integer1/],
        sort_by        => [qw/string1/],
        sort_by_parent => [qw/curval1/],
        sort_type      => ['asc'],
        first          => qr/^(6|7|8|9)$/,
        last           => qr/^(3)$/,
        max_id         => 9,
        min_id         => 3,
        count          => 7,
    },
);

foreach my $multivalue (0..1)
{
    $sheet->clear_not_data(multivalue => $multivalue);

    my $cid_adjust = 9; # For some reason database restarts at same ID second time

    foreach my $sort (@sorts)
    {   my @sort_types = @{$sort->{sort_type}};
        my $sort_by    = $sort->{sort_by};
        my $filter     = $sort->{filter};

        my @sort_by;
        if(my $parents = $sort->{sort_by_parent})
        {   my @children = @$sort_by;
            foreach my $parent (@$parents)
            {   my $cname = shift @children;
                my $id    = $curval->layout->column($cname)->id;
                my $parent_id = $layout->column($parent)->id;
                push @sort_by, "${parent_id}_$id";
            }
        }
        else
        {   @sort_by = map $layout->column($_ || '_id'), @$sort_by;
        }

        my $view = $sheet->views->view_create({
            name     => 'Test view',
            columns  => $sort->{show_columns},
            filter   => $filter,
            sortings => [ [ \@sort_by, $sort_type ] ],
        });

        foreach my $pass (1..$passes)
        {    my $sort_type  = @sort_types==1 && $pass==3
              ? [ $sort_types[0] eq 'asc' ? 'desc' : 'asc' ]
              : \@sort_types;

            $view->view_update({ sortings => [ [ \@sort_by, $sort_type ] ] });
            my $page = $sheet->content->search(
                view     => $view,
                sortings => $sorting,
            );

        ### Test override of sort first     XXX was "pass1"

        {   ok 1, "testing sort $sort->{name} is overriden";

            my $page = $sheet->content->search(
                view     => $view,
                sortings => +{ type => 'desc', id => $layout->column('_id')->id,
            );

            my $first = $sort->{max_id} || 9;
            my $last  = $sort->{min_id} || 3;

            # 1 record per page to test sorting across multiple pages
            $page->window(rows_per_page => 1);

            is $page->row(0)->current_id - $cid_adjust, $first,
               '... first record for sort override';

            if(my $fs = $sort->{first_string})
            {   foreach my $colname (keys %$fs)
                {   is $page->row(0)->cell($colname)->as_string,
                       $sort->{first_string}->{$colname},
                       "... first record value for $colname";
                }
            }

            my $new_pagenr = $sort->{count} || 7;
            $page->window(page_number => $new_pagenr);

            ok defined $new_page, "... moved to other page";
            is $new_page->page_number, $sort->{count} || 7,
               "... moved to page $newpagenr";

            is $new_page->row(-1)->current_id - $cid_adjust,
               $last,
               "... last record for sort override";

            if(my $ls = $sort->{last_string})
            {   foreach my $colname (keys %$ls)
                {   is $page->row(0)->field($colname)->as_string,
                       $sort->{last_string}->{$colname},
                       "last record value for $colname";
                }
            }

            # Basic graph test. Total of points on graph should match the number of results.
            # Even though graphs do not use sorting, so a test with a sort
            # as the user may still be using a view with a sort defined.
            my $axis = $layout->column('string1')->id;
            my $graph = $sheet->graphs->graph_create({
                title        => 'Test',
                type         => 'bar',
                current_user => $sheet->user,
                x_axis       => $axis,
                y_axis       => $axis,
                y_axis_stack => 'count',
                view         => $view,
            });

            # Count total number of records  XXX $graph->content_points?
            my $graph_total = sum map { scalar @$_ }, $graph->content->points->[0]};

            my $count = $sort->{filter} ? $sort->{count} : 7;
            is $graph_total, $count, "Item total on graph matches table for $sort->{name}";
            $sheet->graphs->graph_delete($graph);
        }

        ### Use the sort from the view    XXX was pass2

        {   ok 1, "testing sort $sort->{name}, sort defined by view";

            my $page = $sheet->content->search(view => $view);

            is $page->all_rows, $sort->{count},
                '... number of records in results'
                if $sort->{count};

            like $page->row(0)->current_id - $cid_adjust, $sort->{first},
                 '... first record';

            like $page->row(-1)->current_id - $cid_adjust, $sort->{last},
                '... last record';

            # Then switch to 1 record per page to test sorting across multiple pages
            $page->window(rows_per_page => 1);

            like $page->row(0)->current_id - $cid_adjust, $sort->{first},
                '... correct first record';

            $page->window(page_number => $sort->{count} || 7);

            like $page->row(0)->current_id - $cid_adjust, $sort->{last},
                '... last record';
        }

        ### Reverse sorting     XXX was pass3

        if(@sort_types==1)
        {   ok 1, "testing sort $sort->{name}, sort reversed by view";

            my $rev = $sort_types[0] eq 'asc' ? 'desc' : 'asc';
            $view->view_update({ sortings => [ [ \@sort_by, $rev ] ] });

            my $page = $sheet->content->search(view => $view);

            is $page->all_rows, $sort->{count}, '... number of records in results'
                if $sort->{count};

            like $page->row(0)->current_id - $cid_adjust, $sort->{last},
                '... first record in reverse';

            like $page->row(-1)->current_id - $cid_adjust, $sort->{last},
                '... last record in reverse';

            # Then switch to 1 record per page to test sorting across multiple pages
            $page->window(rows_per_page => 1);

            like( $page->row(0)->current_id - $cid_adjust, $sort->{last}, "Correct first record for sort $sort->{name} in reverse");

                $records->page($sort->{count} || 7);
            like $page->row(0)->current_id - $cid_adjust, $sort->{first}, "Correct last record for sort $sort->{name} in reverse");
        }

        #### Count only    XXX was pass4
        # If doing a count with the sort, then do an extra pass, one to check that actual
        # number of rows retrieved, and one to check the count calculation function
        if(my $count = $sort->{count})
        {   ok 1, "testing sort $sort->{name}, count only";

            my $page = $sheet->content->search(view => $view);
            is $page->count, $count, '... record count';

ok ! $page->_loaded_any_record;
        }

        $sheet->views->view_delete($view);
    }
}

restore_time();

done_testing;
