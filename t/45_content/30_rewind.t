
use Linkspace::Test
    not_ready => 'needs graphs';

foreach my $multivalue (0..1)
{
    # We will use 3 dates for the data: all 10th October, but years 2014, 2015, 2016
    set_fixed_time '10/10/2014 01:00:00', '%m/%d/%Y %H:%M:%S';

    my $sheet = make_sheet 1,
        rows        => [ { string1 => 'Foo1', integer1 => 10 } ],
        multivalues => $multivalue;

    my $layout   = $sheet->layout;
    my $content  = $sheet->content;

    cmp_ok $content->row_count, '==', 1, 'Correct number of records on initial creation';
    my $row = $content->row(1);

    ### Make 2 further writes for subsequent 2 years

    set_fixed_time '10/10/2015 01:00:00', '%m/%d/%Y %H:%M:%S';
    $row->revision_create({ string1 => 'Foo2', integer1 => 20 });

    set_fixed_time '10/10/2016 01:00:00', '%m/%d/%Y %H:%M:%S';
    $row->revision_create({ string1 => 'Foo3', integer1 => 30 });

    # And a new record for the third year
    my $row2 = $content->row_create({
        revision => { string1 => 'Foo10', integer1 => 100 },
    });

    cmp_ok $content->row_count, '==', 2,
       'Correct number of records for today after second write';

    # Go back to initial values (2014)
    my $previous = DateTime->new(year => 2015, month => 01, day => 01, hour => 12);

    # Use rewind feature and check records are as they were on previous date

    my $results1 = $content(rewind => $previous)->search;
    cmp_ok $results1->count, '==', 1,
        'Correct number of records for previous date (2014) $multivalue';

    my $result1 = $results1->row(1);
    is $result1->cell('string1')->as_string, 'Foo1', 'Correct old value for first record (2014)';

    # Go back to second set (2015)
    $previous->add(years => 1);
    my $results2 = $sheet->content(rewind => $previous)->search;
    cmp_ok $results2->count, '==', 1, 'Correct number of records for previous date (2015)';

    my $result2 = $results2->row(1);
    is $result2->cell('string1')->as_string, 'Foo2', 'Correct old value for first record (2015)';

    # And back to today
    my $results3 = $content->search;
    cmp_ok $results3->count, '==', 2, 'Correct number of records for current date';

    my $result3 = $results3->row(1);
    is $result3->cell('string1')->as_string, 'Foo3', 'Correct value for first record current date';

    # Retrieve single record

    my $row4 = $content->row(1);
    is $row4->cell('string1'), 'Foo3',
         'Correct value for first record current date, single retrieve';

    my $vs4 = join ' ', map $_->created->ymd, $row4->versions;
    is $vs4, '2016-10-10 2015-10-10 2014-10-10', 'All versions in live version';

    ### rewind

    my $results5 = $content(rewind => $previous)->search;
    my $result5  = $results5->row(1);
    is $result5->cell('string1')->as_string, 'Foo1', 'Correct old value for first version';

    my $vs5 = join ' ', map $_->created->ymd, $result4->versions;
    is $vs5, '2015-10-10 2014-10-10', 'Only first 2 versions in old version';

    my $row5 = $content->row(2);
    is $row5->cell('string1'), 'Foo2', 'Correct old value for second version';

    # Check cannot retrieve latest version with rewind set as-is

    my $row6 = $content->row(3);
    ok !defined $row6, 'Cannot retrieve version after current rewind setting';

    # Try an edit - should bork

    try { $row6->cell_update(string1 => 'Bar') };
    ok($@, 'Unable to write to record from historic retrieval');

    # Do a graph check from a rewind date
    my $graph = $sheet->graphs->graph_create({
        title        => 'Rewind graph',
        type         => 'bar',
        x_axis       => 'string1',
        y_axis       => 'integer1',
        y_axis_stack => 'sum',
    );

    my $graph_data1 = $sheet->content->search->graph($graph);
    ok defined $graph_data1, "Created graph, now";
    is_deeply $graph_data1->xlabels, ['Foo10','Foo3'], '... xlabels';
    is_deeply $graph_data1->points, [[100,30]], '... points';

    my $graph_data2 = $sheet->content(rewind => $previous)->search->graph($graph);
    ok defined $graph_data2, "Created graph, rewinded";
    is_deeply $graph_data2->xlabels, ['Foo2'], '... xlabels';
    is_deeply $graph_data2->points, [[20]], '... points';
}

done_testing;
