# Derived from t/005_dateformat.t
use Linkspace::Test
    not_ready => 'Needs constructing sheets';

my $tests = {
    'yyyy-MM-dd' => {
        data => [
            {
                date1      => '2010-10-10',
                daterange1 => ['2000-10-10', '2001-10-10'],
            },
            {
                date1      => '2011-10-10',
                daterange1 => ['2009-08-10', '2012-10-10'],
            },
            {
                date1      => '2001-10-10',
                daterange1 => ['2008-08-10', '2011-10-10'],
            },
        ],
        search => {
            valid   => '2010-10-10',
            invalid => '10-10-2010',
            calc    => '2008-08-10',
        },
        retrieved => {
            date      => '2010-10-10',
            daterange => '2009-08-10 to 2012-10-10',
        },
    },
    'dd-MM-yyyy' => {
        data => [
            {
                date1      => '10-10-2010',
                daterange1 => ['10-10-2000', '10-10-2001'],
            },
            {
                date1      => '10-10-2011',
                daterange1 => ['10-08-2009', '10-10-2012'],
            },
            {
                date1      => '10-10-2001',
                daterange1 => ['10-08-2008', '10-10-2011'],
            },
        ],
        search => {
            valid   => '10-10-2010',
            invalid => '2010-10-10',
            calc    => '10-08-2008',
        },
        retrieved => {
            date      => '10-10-2010',
            daterange => '10-08-2009 to 10-10-2012',
        },
    },
};

my $site_nr = 0;

foreach my $format (qw/yyyy-MM-dd dd-MM-yyyy/)
{
#XXX would like to simply reconfig test-site, but ::CLDR objects are pre-compiled
    my $site = make_site ++$site_nr, language => { date_format => $format };
    my $test = $tests->{$format};

    my $sheet = make_sheet 1,
        site             => $site,
        rows             => $test->{data},
        calc_code        => "function evaluate (L1daterange1) \n return L1daterange1.from.epoch \n end",
        calc_return_type => 'date',
    );
    my $layout  = $sheet->layout;

    ### First test: check format of date column with search

    my $rules1 = { rule => {
        column   => 'date1',
        operator => 'equal',
        value    => $test->{search}{valid},
    }};

    my $view1 = $sheet->view_create({
        name        => 'Test view1',
        filter      => $rules1,
        columns     => [ 'date1', 'date2' ],
    });

    my $results1 = $sheet->content->search(view => $view1);
    cmp_ok $results1->count, '==', 1, "Correct number of records for date search";

    is $results1->row(0)->cell('date1')->as_string, $test->{retrieved}{date},
        'Date format correct for retrieved record';

    ### Check additional date filter as used in calendar

    my $results2 = $sheet->content->search(
        view    => $view1,
        from    => DateTime->new(year => 2010, month => 10, day => 1),
        to      => DateTime->new(year => 2010, month => 11, day => 1),
    );
    cmp_ok $results2->count, '==', 1, "Correct number of records for date filter and additional search";
    cmp_ok @{$results2->data_calendar}, '==', 1,
       'Correct number of records for date filter and additional search';

    ### check format of daterange column with search

    my $rules3 = { rule => {
        column   => 'daterange1',
        type     => 'date',
        value    => $test->{search}{valid},
        operator => 'contains',
    }};

    my $view3 = $sheet->views->view_create({
        name        => 'Test view3',
        filter      => $rules3,
        columns     => [ 'date1', 'date2' ],
    });

    my $results3 = $sheet->content->search(view => $view3);
    cmp_ok $results3->count, '==', 2, "Correct number of records for daterange search";

    is $results3->row(0)->cell('daterange1')->as_string,
       $test->{retrieved}{daterange}, "Date range format correct for retrieved record";

    ### Try searching for the calc value

    my $rules4 = { rules => {
        column   => 'calc1',
        type     => 'date',
        operator => 'equal',
        value    => $test->{search}{calc},
    }};

    my $view4 = $sheet->views->view_create({
        name        => 'Test view4',
        filter      => $rules4,
        columns     => [ 'date1', 'date2' ],
    });

    my $results4 = $sheet->content->search(view => $view4);
    cmp_ok $results4->count, '==', 1, "Correct number of records for calc date search, format $format";

    ### Try a quick search for date field

    my $results5 = $sheet->content->search($test->{search}{valid});
    cmp_ok $results5->nr_rows, '==', 1, "Correct number of results for quick search, format $format";

    ### Try a quick search for calc field

    my $results6 = $sheet->content->search($test->{search}{calc});
    cmp_ok $results6->nr_rows, '==', 1, "Correct number of results for quick search for calc, format $format";

    ### Try creating a filter with invalid date format

    my $rules7 = { rule => {
        column   => 'date1',
        operator => 'equal',
        value    => $test->{search}{invalid},
    }};

    my $view7 = try { $sheet->views->view_create({
        name        => 'Test view7',
        filter      => $rules7,
        columns     => [ 'date1', 'date2' ],
    }) };
    ok $@, "Attempt to create filter with invalid date failed";

    ### Try creating a filter with empty string (invalid)

    my $rules8 = { rule => {
        column   => 'date1',
        operator => 'equal',
        value    => '',
    }};
    my $view8 = try { $sheet->views->view_create({
        name        => 'Test view8',
        filter      => $rules8,
        columns     => [ 'date1', 'date2' ],
    }) };
    ok $@, "Attempt to create filter with empty string failed";
}

done_testing;
