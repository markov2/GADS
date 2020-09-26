use Test::More; # tests => 1;
use strict;
use warnings;

use Test::MockTime qw(set_fixed_time restore_time); # Load before DateTime
use DateTime;
use JSON qw(encode_json);
use Log::Report;
use GADS::Graph;
use GADS::Graph::Data;
use GADS::Record;
use GADS::Records;
use GADS::RecordsGraph;

use t::lib::DataSheet;

$ENV{GADS_NO_FORK} = 1;

my $data = [ { string1 => 'Foo1', integer1 => 10 } ];

foreach my $multivalue (0..1)
{
    # We will use 3 dates for the data: all 10th October, but years 2014, 2015, 2016
    set_fixed_time('10/10/2014 01:00:00', '%m/%d/%Y %H:%M:%S');

    my $sheet = make_sheet rows => $data, multivalues => $multivalue);
    $sheet->create_records;

    my $schema   = $sheet->schema;
    my $layout   = $sheet->layout;
    my $string1  = $sheet->columns->{string1};
    my $integer1 = $sheet->columns->{integer1};

    cmp_ok $sheet->content->nr_rows, '==', 1, "Correct number of records on initial creation";
    my $row = $sheet->content->row(1);

    # Make 2 further writes for subsequent 2 years
    set_fixed_time('10/10/2015 01:00:00', '%m/%d/%Y %H:%M:%S');
    $row->revision_create({ string1 => 'Foo2', integer1 => 20 });

    set_fixed_time('10/10/2016 01:00:00', '%m/%d/%Y %H:%M:%S');
    $row->revision_create({ string1 => 'Foo3', integer1 => 30 });

    # And a new record for the third year
    my $row2 = $sheet->content->row_create({});
    $row2->revision_create({ string1 => 'Foo10', integer1 => 100 });

    cmp_ok $sheet->content->nr_rows, '==', 2,
       "Correct number of records for today after second write";

    # Go back to initial values (2014)
    my $previous = DateTime->new(
        year       => 2015,
        month      => 01,
        day        => 01,
        hour       => 12,
    );

    # Use rewind feature and check records are as they were on previous date

    my $results1 = $sheet->content(rewind => $previous)->search;
    cmp_ok $results1->count, '==', 1,
        "Correct number of records for previous date (2014) $multivalue";

    my $result1 = $results1->row(1);
    is $result1->cell('string1')->as_string, 'Foo1', "Correct old value for first record (2014)";

    # Go back to second set (2015)
    $previous->add(years => 1);
    my $results2 = $sheet->content(rewind => $previous)->search;
    cmp_ok $results2->count, '==', 1, "Correct number of records for previous date (2015)";

    my $result2 = $results2->row(1);
    is $result2->cell('string1')->as_string, 'Foo2', "Correct old value for first record (2015)";

    # And back to today
    my $results3 = $sheet->content->search;
    cmp_ok $results3->count, '==', 2, "Correct number of records for current date";

    my $result3 = $results3->row(1);
    is $result3->cell('string1')->as_string, 'Foo3', "Correct value for first record current date";

    # Retrieve single record

    my $row1 = $sheet->content->row(1);
    is $row1->cell('string1')->as_string, 'Foo3',
         "Correct value for first record current date, single retrieve";

    my $vs1 = join ' ', map $_->created->ymd, $row1->versions;
    is $vs1, "2016-10-10 2015-10-10 2014-10-10", "All versions in live version";

 ### rewind

    my $results4 = $sheet->content(rewind => $previous)->search;
    my $result4  = $results4->row(1);
    is $result4->cell('string1')->as_string, 'Foo1', "Correct old value for first version";

    my $vs4 = join ' ', map $_->created->ymd, $result4->versions;
    is $vs4, "2015-10-10 2014-10-10", "Only first 2 versions in old version";

    my $row2 = $sheet->content->row(2);
    is $row2->cell('string1')->as_string, 'Foo2', "Correct old value for second version";

    # Check cannot retrieve latest version with rewind set as-is
    my $row3 = $sheet->content->row(3);
    ok !defined $row3, "Cannot retrieve version after current rewind setting";

    # Try an edit - should bork

    try { $row2->cell_update(string1 => 'Bar') };
    ok($@, "Unable to write to record from historic retrieval");

    # Do a graph check from a rewind date
    my $graph = $sheet->graphs->graph_create({
        title        => 'Rewind graph',
        type         => 'bar',
        x_axis       => 'string1',
        y_axis       => 'integer1',
        y_axis_stack => 'sum',
    );

    $records = GADS::RecordsGraph->new(
        user    => $sheet->user,
        layout  => $layout,
        schema  => $schema,
    );
    my $graph_data = GADS::Graph::Data->new(
        id      => $graph->id,
        records => $records,
        schema  => $schema,
    );

    is_deeply $graph_data->xlabels, ['Foo10','Foo3'], "Graph labels for current date correct";
    is_deeply $graph_data->points, [[100,30]], "Graph data for current date correct";

    $records = GADS::RecordsGraph->new(
        user    => $sheet->user,
        layout  => $layout,
        schema  => $schema,
        rewind  => $previous,
    );
    $graph_data = GADS::Graph::Data->new(
        id      => $graph->id,
        records => $records,
        schema  => $schema,
    );
    is_deeply $graph_data->xlabels, ['Foo2'], "Graph data for previous date is correct";
    is_deeply $graph_data->points, [[20]], "Graph labels for previous date is correct";
}

restore_time;

done_testing;
