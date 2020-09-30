
use Linkspace::Test;

set_fixed_time('01/01/2015 12:00:00', '%m/%d/%Y %H:%M:%S');

my $sheet_nr = 1;
foreach my $multivalue (0..1)
{
    my $linked_value = 10; # See below
    my $linked_enum  = 13; # ID for foo1

    my $data = [
        {
            # No integer1 or enum1 - the value will be taken from a linked record ($linked_value).
            # integer1 will be 10, enum1 will be equivalent of 7.
            string1    => 'Foo',
            date1      => '2013-10-10',
            daterange1 => ['2014-03-21', '2015-03-01'],
            tree1      => 'tree1',
            curval1    => 1,
            integer2   => 8,
        },{
            string1    => $multivalue ? ['Bar', 'FooBar'] : 'Bar',
            date1      => '2014-10-10',
            daterange1 => ['2010-01-04', '2011-06-03'],
            integer1   => 150, # Changed to 15
            enum1      => 7,
            tree1      => 'tree1',
            curval1    => 2,
            integer2   => 80, # Changed to 8
        },{
            string1    => 'Bar',
            integer1   => 35,
            enum1      => 8,
            tree1      => 'tree1',
            curval1    => 1,
            integer2   => 24,
        },{
            string1    => 'FooBar',
            date1      => '2016-10-10',
            daterange1 => ['2009-01-04', '2017-06-03'],
            integer1   => 20,
            enum1      => $multivalue ? [8, 9] : 8,
            tree1      => 'tree1',
            curval1    => 2,
            integer2   => 13,
        },
    ];

    my $curval_sheet = test_sheet $sheet_nr++ , multivalues => $multivalue;

    # Make an edit to a curval record, to make sure that only the latest
    # version is used in the graphs

    $curval_sheet->content->row(2)->cell_update(integer1 => 132);

    my $sheet   = make_sheet 1,
        rows               => $data,
        curval_sheet       => $curval_sheet,
        column_count       => { integer => 2 },
        multivalue_columns => $multivalue ? [ qw/enum string/ ] : undef,
    );
    my $layout  = $sheet->layout;

    $layout->column_create({
        name          => 'calc2',
        return_type   => 'integer',
        code          => "function evaluate (L1integer2) \n return {L1integer2, L1integer2 * 2} \nend",
        is_multivalue => 1,
    });

    # Make an edit to a curval record, to make sure that only the latest
    # version is used in the graphs
    $sheet->content->row(4)->revision_update({ integer1 => 15, integer2 => 8 });

    # Add linked record sheet, which will contain the integer1 value for the first
    # record of the first sheet
    my $sheet2  = make_sheet 2, rows => [];
    my $layout2 = $sheet2->layout;

    # Set link field of first sheet integer1 to integer1 of second sheet
    $layout->column_update($_ => { link_parent => $layout2->column($_) })
        for qw/integer1 enum1/;

    # Create the single record of the second sheet, which will contain the single
    # integer1 value
    $sheet2->content->row_create({ integer1 => $linked_value, enum1 => $linked_enum });

    # Set the first record of the first sheet to take its value from the linked sheet
    my $parent = $sheet->content->search->row(1);
    #$parent->linked_id($child->current_id);
    $parent->write_linked_id($child->current_id);   #XXX

    my $graphs = [
        {
            name         => 'String x-axis, integer sum y-axis',
            type         => 'bar',
            x_axis       => 'string1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            data         => [[ 50, 10, $multivalue ? 35 : 20 ]],
        },
        {
            name         => 'String x-axis, multi-integer sum y-axis',
            type         => 'bar',
            x_axis       => 'string1',
            y_axis       => 'calc2',
            y_axis_stack => 'sum',
            data         => [[ 96, 24, $multivalue ? 63 : 39 ]],
            xlabels      => [qw/Bar Foo FooBar/],
        },
        {
            name         => 'String x-axis, multi-integer sum y-axis, filtered',
            type         => 'bar',
            x_axis       => 'string1',
            y_axis       => 'calc2'
            y_axis_stack => 'sum',
            data         => [[ 72, 26 ]],
            xlabels      => [qw/Bar FooBar/],
            rules => [
                {
                    column   => 'calc2'
                    type     => 'string',
                    operator => 'greater',
                    value    => '20',
                }
            ],
        },
        {
            name         => 'Integer x-axis, count y-axis',
            type         => 'bar',
            x_axis       => 'integer2',
            y_axis       => 'string1',
            y_axis_stack => 'count',
            data         => [[ 1, 1, 2 ]],
            xlabels      => [qw/13 24 8/],
        },
        {
            name         => 'String x-axis, integer sum y-axis as percent',
            type         => 'bar',
            x_axis       => 'string1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            as_percent   => 1,
            data         => $multivalue ? [[ 53, 11, 37 ]] : [[ 63, 13, 25 ]],
        },
        {
            name         => 'Pie as percent',
            type         => 'pie',
            x_axis       => 'string1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            as_percent   => 1,
            data         => $multivalue
                ? [[[ 'Bar', 53 ], [ 'Foo', 11 ], ['FooBar', 37 ]]]
                : [[[ 'Bar', 63 ], [ 'Foo', 13 ], ['FooBar', 25 ]]],
        },
        {
            name         => 'Pie with blank value',
            type         => 'pie',
            x_axis       => 'date1',
            y_axis       => 'string1',
            y_axis_stack => 'count',
            # Jqplot seems to want labels encoded only for pie graphs
            data         => [[['2013-10-10', 1], ['2014-10-10', 1], ['2016-10-10', 1], ['&lt;no value&gt;', 1]]],
        },
        {
            name         => 'String x-axis, integer sum y-axis with view filter',
            type         => 'bar',
            x_axis       => 'string1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            data         => $multivalue ? [[ 15, 10, 15 ]] : [[ 15, 10 ]],
            rules => [
                {
                    column   => 'enum1',
                    type     => 'string',
                    value    => 'foo1',
                    operator => 'equal',
                }
            ],
        },
        {
            name            => 'Date range x-axis, integer sum y-axis',
            type            => 'bar',
            x_axis          => 'daterange1',
            x_axis_grouping => 'year',
            y_axis          => 'integer1',
            y_axis_stack    => 'sum',
            data            => [[ 20, 35, 35, 20, 20, 30, 30, 20, 20 ]],
        },
        {
            name            => 'Date range x-axis, integer sum y-axis, limited time period by dates',
            type            => 'bar',
            x_axis          => 'daterange1',
            x_axis_grouping => 'year',
            y_axis          => 'integer1',
            y_axis_stack    => 'sum',
            from            => DateTime->new(year => 2013, month => 8, day => 15),
            to              => DateTime->new(year => 2016, month => 6, day => 15),
            data            => [[ 20, 30, 30, 20 ]],
            xlabels         => [qw/2013 2014 2015 2016/],
        },
        {
            name            => 'Date range x-axis, integer sum y-axis, limited time period by length',
            type            => 'bar',
            x_axis          => 'daterange1',
            x_axis_range    => 6,
            y_axis          => 'integer1',
            y_axis_stack    => 'sum',
            data            => [[ 30, 30, 30, 20, 20, 20, 20 ]],
            xlabels         => ['January 2015', 'February 2015', 'March 2015', 'April 2015', 'May 2015', 'June 2015', 'July 2015'],
        },
        {
            name            => 'Date range x-axis, integer sum y-axis, limited time period by length negative',
            type            => 'bar',
            x_axis          => 'daterange1',
            x_axis_range    => -6,
            y_axis          => 'integer1',
            y_axis_stack    => 'sum',
            data            => [[ 30, 30, 30, 30, 30, 30, 30 ]],
            xlabels         => ['July 2014', 'August 2014', 'September 2014', 'October 2014', 'November 2014', 'December 2014', 'January 2015'],
        },
        {
            name            => 'Date range x-axis from curval, integer sum y-axis',
            type            => 'bar',
            x_axis          => $curval_layout->column('daterange1'),
            x_axis_link     => 'curval1',
            x_axis_grouping => 'year',
            y_axis          => 'integer1',
            y_axis_stack    => 'sum',
            data            => [[ 35, 0, 0, 0, 45, 45 ]],
        },
        {
            name            => 'Date range x-axis from curval, integer sum y-axis, group by curval',
            type            => 'bar',
            x_axis          => $curval_layout->column('daterange1'),
            x_axis_link     => 'curval1',
            x_axis_grouping => 'year',
            y_axis          => 'integer1',
            y_axis_stack    => 'sum',
            group_by        => 'curval1',
            data            => [[ 0, 0, 0, 0, 45, 45 ], [ 35, 0, 0, 0, 0, 0 ]],
            labels       => [
                'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012',
                'Bar, 132, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
            ],
        },
        {
            name            => 'Date x-axis, integer count y-axis',
            type            => 'bar',
            x_axis          => 'date1',
            x_axis_grouping => 'year',
            y_axis          => 'string1',
            y_axis_stack    => 'count',
            data            => [[ 1, 1, 0, 1 ]],
        },
        {
            name            => 'Date x-axis, integer count y-axis, limited range',
            type            => 'bar',
            x_axis          => 'date1',
            x_axis_grouping => 'year',
            y_axis          => 'string1',
            y_axis_stack    => 'count',
            from            => DateTime->new(year => 2014, month => 1, day => 15),
            to              => DateTime->new(year => 2016, month => 12, day => 15),
            data            => [[ 1, 0, 1 ]],
            xlabels         => [qw/2014 2015 2016/],
        },
        {
            name            => 'Date x-axis, integer sum y-axis, limited range by length',
            type            => 'bar',
            x_axis          => 'date1',
            x_axis_range    => 120,
            y_axis          => 'integer1',
            y_axis_stack    => 'sum',
            data            => [[ 0, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0 ]],
            xlabels         => [qw/2015 2016 2017 2018 2019 2020 2021 2022 2023 2024 2025/],
        },
        {
            name            => 'Date x-axis, integer sum y-axis, limited range by length, grouped',
            type            => 'bar',
            x_axis          => 'date1',
            x_axis_range    => -120,
            y_axis          => 'integer1',
            y_axis_stack    => 'sum',
            group_by        => 'enum1',
            data            => [
                [ 0, 0, 0, 0, 0, 0, 0, 0, 10, 15, 0 ],
            ],
            xlabels         => [qw/2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015/],
            labels          => [qw/foo1/],
        },
        {
            name            => 'Date x-axis, integer sum y-axis, limited range by dates, grouped',
            type            => 'bar',
            x_axis          => 'date1',
            x_axis_grouping => 'year',
            x_axis_range    => 'custom',
            from            => DateTime->new(year => 2012, month => 1, day => 15),
            to              => DateTime->new(year => 2018, month => 12, day => 15),
            y_axis          => 'integer1',
            y_axis_stack    => 'sum',
            group_by        => 'enum1',
            data            => $multivalue
            ? [
                [ 0, 0, 0, 0, 20, 0, 0 ],
                [ 0, 0, 0, 0, 20, 0, 0 ],
                [ 0, 10, 15, 0, 0, 0, 0 ],
            ]
            : [
                [ 0, 0, 0, 0, 20, 0, 0 ],
                [ 0, 10, 15, 0, 0, 0, 0 ],
            ],
            xlabels         => [qw/2012 2013 2014 2015 2016 2017 2018/],
            labels          => $multivalue ? [qw/foo3 foo2 foo1/] : [qw/foo2 foo1/],
        },
        {
            name         => 'String x-axis, sum y-axis, group by enum',
            type         => 'bar',
            x_axis       => 'string1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            group_by     => 'enum1',
            data         => $multivalue ? [[ 0, 0, 20 ], [ 35, 0, 20 ], [ 15, 10, 15 ]] : [[ 35, 0, 20 ], [ 15, 10, 0 ]],
        },
        {
            name         => 'String x-axis, sum y-axis, group by enum as percent',
            type         => 'bar',
            x_axis       => 'string1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            group_by     => 'enum1',
            as_percent   => 1,
            data         => $multivalue ? [[ 0, 0, 36 ], [ 70, 0, 36 ], [ 30, 100, 27 ]] : [[ 70, 0, 100 ], [ 30, 100, 0 ]],
        },
        {
            name         => 'Filter on multi-value enum',
            type         => 'bar',
            x_axis       => 'string1',
            y_axis       => 'integer1',
            y_axis_stack => 'count',
            data         => [[ 1, 1 ]],
            rules => [
                {
                    id       => 'enum1',
                    type     => 'string',
                    value    => 'foo2',
                    operator => 'equal',
                },
                {
                    id       => 'enum1',
                    type     => 'string',
                    value    => 'foo3',
                    operator => 'equal',
                }
            ],
            condition => 'OR',

        },
        {
            name         => 'Curval on x-axis',
            type         => 'bar',
            x_axis       => 'curval1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            data         => [[ 35, 45 ]],
        },
        {
            name         => 'Field from curval on x-axis',
            type         => 'bar',
            x_axis       => $curval_layout->column('string1'),
            x_axis_link  => 'curval1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            data         => [[ 35, 45 ]],
            xlabels      => ['Bar', 'Foo'],
        },
        {
            name         => 'Enum field from curval on x-axis',
            type         => 'bar',
            x_axis       => $curval_layout->column('enum1'),
            x_axis_link  => 'curval1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            data         => [[ 45, 35 ]],
            xlabels      => ['foo1', 'foo2'],
        },
        {
            name         => 'Enum field from curval on x-axis, enum on y, with filter',
            type         => 'bar',
            x_axis       => $curval_layout->column('enum1'),
            x_axis_link  => 'curval1',
            y_axis       => 'tree1',
            y_axis_stack => 'count',
            data         => [[ 1, 1 ]],
            xlabels      => ['foo1', 'foo2'],
            rules => [
                {
                    column   => 'enum1',
                    type     => 'string',
                    value    => 'foo1',
                    operator => 'equal',
                }
            ],
        },
        {
            name         => 'Curval on x-axis grouped by enum',
            type         => 'bar',
            x_axis       => 'curval1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            group_by     => 'enum1',
            data         => $multivalue ? [[ 20, 0 ], [ 20, 35 ], [ 15, 10 ]] : [[ 20, 35 ], [ 15, 10 ]],
        },
        {
            name         => 'Enum on x-axis, filter by enum',
            type         => 'bar',
            x_axis       => 'enum1',
            y_axis       => 'string1',
            y_axis_stack => 'count',
            data         => $multivalue ? [[ 2, 2, 1 ]] : [[ 2, 2 ]],
            rules => [
                {
                    column   => 'tree1'
                    type     => 'string',
                    value    => 'tree1',
                    operator => 'equal',
                }
            ],
        },
        {
            name         => 'Curval on x-axis, filter by enum',
            type         => 'bar',
            x_axis       => 'curval1',
            y_axis       => 'string1',
            y_axis_stack => 'count',
            data         => [[ 1, 1 ]],
            rules => [
                {
                    column   => 'enum1',
                    type     => 'string',
                    value    => 'foo1',
                    operator => 'equal',
                }
            ],
        },
        {
            name         => 'Graph grouped by curvals',
            type         => 'bar',
            x_axis       => 'string1',
            y_axis       => 'integer1',
            y_axis_stack => 'sum',
            group_by     => 'curval1',
            data         => $multivalue ? [[ 35, 10, 0 ], [ 15, 0, 35 ]] : [[ 35, 10, 0 ], [ 15, 0, 20 ]],
            labels       => [
                'Foo, 50, foo1, , 2014-10-10, 2012-02-10 to 2013-06-15, , , c_amber, 2012',
                'Bar, 132, foo2, , 2009-01-02, 2008-05-04 to 2008-07-14, , , b_red, 2008',
            ],
        },
        {
            name         => 'Linked value on x-axis, count',
            type         => 'bar',
            x_axis       => 'integer1',
            y_axis       => 'string1',
            y_axis_stack => 'count',
            data         => [[ 1, 1, 1, 1 ]],
            xlabels      => [ 10, 15, 20, 35 ],
        },
        {
            name         => 'Linked value on x-axis (multiple linked), count',
            type         => 'bar',
            x_axis       => 'integer1',
            y_axis       => 'string1',
            y_axis_stack => 'count',
            data         => [[ 1, 1, 1, 1 ]],
            xlabels      => [ 10, 20, 35, 55 ],
            child2       => 55,
        },
        {
            name         => 'Linked value on x-axis (same value in normal/linked), sum',
            type         => 'bar',
            x_axis       => 'integer1',
            y_axis       => 'calc1',
            y_axis_stack => 'sum',
            data         => [[ 4024, 2009, 0 ]],
            xlabels      => [ 15, 20, 35 ],
            child        => 15,
        },
        {
            name         => 'All columns x-axis, sum y-axis',
            type         => 'bar',
            x_axis       => undef,
            y_axis       => 'integer1', # Can be anything
            y_axis_stack => 'sum',
            data         => [[ 25 ]],
            view_columns => ['integer1'],
            rules => [
                {
                    column   => 'enum1',
                    type     => 'string',
                    value    => 'foo1',
                    operator => 'equal',
                }
            ],
        },
    ];

XXX
    foreach my $g (@$graphs)
    {
        # Write new linked value, or reset to original
        my $child_value = $g->{child} || $linked_value;
        my $child_id = $child->current_id;
        $child->clear;
        $child->find_current_id($child_id);
        my $datum = $child->fields->{$columns2->{integer1}->id};
        if ($datum->value != $child_value)
        {
            $datum->set_value($child_value);
            $child->write(no_alerts => 1);
        }

        my $child2; my $parent2;
        if (my $child2_value = $g->{child2})
        {
            $child2 = GADS::Record->new(
                user   => $sheet->user,
                layout => $layout2,
                schema => $schema,
            );
            $child2->initialise;
            $child2->fields->{$columns2->{integer1}->id}->set_value($child2_value);
            $child2->write(no_alerts => 1);
            # Set the first record of the first sheet to take its value from the linked sheet
            $parent2 = GADS::Record->new(
                user   => $sheet->user,
                layout => $layout,
                schema => $schema,
            )->find_current_id(4);
            $parent2->write_linked_id($child2->current_id);
        }


### 2020-09-30: columns in GADS::Schema::Result::Graph
# id              description     stackseries     x_axis_range
# instance_id     from            to              y_axis
# title           group_by        trend           y_axis_label
# type            group_id        x_axis          y_axis_stack
# user_id         is_shared       x_axis_grouping
# as_percent      metric_group    x_axis_link

        my $name = $g->{title} = delete $g->{name};
        ok 1, "Create graph $name";

        if(my $rules   = delete $g->{rules})
        {   my %filter = (
                rules     => $r,
                condition => delete $g->{condition} || 'AND',
            );

            $view = $sheet->views->view_create({
                name        => "Test view $name",
                filter      => \%filter,
                columns     => delete $g->{view_columns} || [],
            );
            $view->write;
        }


        my $graph = $sheet->graphs->graph_create($g);

        my $records = GADS::RecordsGraph->new(
            user              => $sheet->user,
            layout            => $layout,
            schema            => $schema,
        );
        my $graph_data = $sheet->content->search(view => $view)->graph($graph);

        is_deeply $graph_data->points,  $g->{data},    '... points as expected';
        is_deeply $graph_data->xlabels, $g->{xlabels}, '... xlabels as expected'
            if $g->{xlabels};

        if($g->{labels})
        {   my @labels = map $_->{label}, @{$graph_data->labels};
            is_deeply \@labels, $g->{labels}, '... labels as expected';
        }

        if($child2)
        {   $parent2->write_linked_id(undef);
            #XXX parent2 a Row::Revision, and $child2 a Row?
            $parent2->purge; # Just the record, revert to previous version XXX
            $child2->purge;
        }
    }
}

# Test graph of large number of records
my @data = 

my $sheet = make_sheet 1,
    rows    => [ map +{ string1 => 'foobar', integer1 => 2}, 1..1000 ],
    columns => [ 'string1', 'integer1' ];

my $graph = $sheet->graphs->graph_create({
    title        => 'Test graph',
    type         => 'bar',
    x_axis       => 'string1',
    y_axis       => 'integer1',
    y_axis_stack => 'sum',
});

my $graph_data = $sheet->content->search->graph($graph);

is_deeply $graph_data->points, [[2000]],
    "Graph data for large number of records is correct";

done_testing;
