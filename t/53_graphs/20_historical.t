# Rewrite from t/012_graph_historical.t

use Linkspace::Test
    not_ready => 'needs graphs';

use Linkspace::Util    qw(iso2datetime);

set_fixed_time '06/14/2019 01:00:00', '%m/%d/%Y %H:%M:%S';

my @records = (
    [
        {
            created => '2018-02-01T11:00',
            data    => {
                enum1    => 1,
                integer1 => 12,
            }
        },
        {
            created => '2018-10-01T12:00',
            data    => {
                enum1    => 2,
                integer1 => 1,
            }
        },
        {
            created => '2019-03-15T18:00',
            data    => {
                enum1    => 3,
                integer1 => 4,
            }
        },
        {
            created => '2019-06-14T01:00',
            data    => {
                enum1    => 2,
                integer1 => 10,
            }
        },
    ],
    [
        {
            created => '2018-06-20T20:00',
            data    => {
                enum1    => 2,
                integer1 => 23,
            }
        },
        {
            created => '2018-07-31T00:00',
            data    => {
                enum1    => 3,
                integer1 => 5,
            }
        },
        {
            created => '2018-11-12T23:59',
            data    => {
                enum1    => 1,
                integer1 => 7,
            }
        },
        {
            created => '2019-04-01T14:50',
            data    => {
                enum1    => 1,
                integer1 => 19,
            }
        },
    ],
    [
        {
            created => '2017-05-13T16:00',
            data    => {
                enum1    => 3,
                integer1 => 1,
            }
        },
        {
            created => '2018-10-01T19:00',
            data    => {
                enum1    => 1,
                integer1 => 0,
            }
        },
        {
            created => '2019-06-02T22:00',
            data    => {
                enum1    => 3,
                integer1 => 54,
            }
        },
        {
            created => '2019-06-02T23:00',
            data    => {
                enum1    => 1,
                integer1 => 37,
            }
        },
    ],
);

my $sheet   = make_sheet rows => [];
my $layout  = $sheet->layout;

foreach my $rec (@records)
{   foreach my $version (@$rec)
    {   my %data = %{$version->{data}};
        $data{_version_datetime} = iso2datetime($version->{created};
        $sheet->content->row_create( { revision => \%data } );
    }
}

is($schema->resultset('Current')->count, 3, "Correct number of records created");
is($schema->resultset('Record')->count, 12, "Correct number of versions created");

my $graphs = [
    {
        name         => 'String x-axis with count - standard 12 month range',
        type         => 'bar',
        x_axis       => 'enum1',
        x_axis_range => '-12',
        y_axis_stack => 'count',
        labels       => [qw/foo3 foo2 foo1/],
        data         => [
            [1,2,2,2,1,0,0,0,0,1,1,1,0],
            [1,0,0,0,1,1,1,1,1,0,0,0,1],
            [1,1,1,1,1,2,2,2,2,2,2,2,2],
        ],
        xlabels => [
          'June 2018', 'July 2018', 'August 2018', 'September 2018',
          'October 2018', 'November 2018', 'December 2018', 'January 2019',
          'February 2019', 'March 2019', 'April 2019', 'May 2019', 'June 2019'
        ],
    },
    {
        name         => 'String x-axis with y-axis sum - standard 12 month range',
        type         => 'bar',
        x_axis       => 'enum1',
        x_axis_range => '-12',
        y_axis       => 'integer1',
        y_axis_stack => 'sum',
        labels       => [qw/foo3 foo2 foo1/],
        data         => [
            [1,6,6,6,5,0,0,0,0,4,4,4,0],
            [23,0,0,0,1,1,1,1,1,0,0,0,10],
            [12,12,12,12,0,7,7,7,7,7,19,19,56],
        ],
        xlabels => [
          'June 2018', 'July 2018', 'August 2018', 'September 2018',
          'October 2018', 'November 2018', 'December 2018', 'January 2019',
          'February 2019', 'March 2019', 'April 2019', 'May 2019', 'June 2019'
        ],
    },
    {
        name         => 'String x-axis with y-axis sum - 1 month range',
        type         => 'bar',
        x_axis       => 'enum1',
        x_axis_range => '-1',
        y_axis       => 'integer1',
        y_axis_stack => 'sum',
        labels       => [qw/foo3 foo2 foo1/],
        data         => [
            [(4) x 31, 0],
            [(0) x 31, 10],
            [(19) x 19, (56) x 13],
        ],
        xlabels => [
          '14 May 2019', '15 May 2019', '16 May 2019', '17 May 2019', '18 May 2019', '19 May 2019',
          '20 May 2019', '21 May 2019', '22 May 2019', '23 May 2019', '24 May 2019', '25 May 2019',
          '26 May 2019', '27 May 2019', '28 May 2019', '29 May 2019', '30 May 2019', '31 May 2019',
          '01 June 2019', '02 June 2019', '03 June 2019', '04 June 2019', '05 June 2019', '06 June 2019',
          '07 June 2019', '08 June 2019', '09 June 2019', '10 June 2019', '11 June 2019', '12 June 2019',
          '13 June 2019', '14 June 2019'
        ]
    },
    {
        name            => 'String x-axis with y-axis count - custom range',
        type            => 'bar',
        x_axis          => 'enum1',
        x_axis_range    => 'custom',
        x_axis_grouping => 'month',
        from            => DateTime->new(year => 2018, month => 1, day => 5),
        to              => DateTime->new(year => 2018, month => 3, day => 10),
        y_axis          => 'integer1',
        y_axis_stack    => 'count',
        labels          => [qw/foo3 foo1/],
        data            => [
            [1,1,1],
            [0,1,1],
        ],
        xlabels => [
          'January 2018', 'February 2018', 'March 2018',
        ],
    },
];

foreach my $g (@$graphs)
{
    my $name  = $g->{title} = delete $g->{name};
    $g->{trend} = 'aggregate';

    my $graph = $sheet->graphs->graph_create($g);
    ok defined $graph, "Graph $name";

    my $graph_data = $sheet->content->search->graph($graph);
    ok defined $graph_data, '... data';

    is_deeply $graph_data->points, $g->{data}, '... points';
    is_deeply $graph_data->xlabels, $g->{xlabels}, '... xlabels';
    my @labels = map $_->{label}, @{$graph_data->labels};
    is_deeply \@labels, $g->{labels}, '... labels';
}

done_testing;
