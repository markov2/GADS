# Rewrite from t/022_download.t

use Linkspace::Test
    not_ready => 'waiting on views and csv';

my @data  = map +[ string1  => 'foobar', integer1 => $_ }, 1..1000;

my $sheet = make_sheet rows => \@data;

my $view = $sheet->views->view_create({
    name         => "Test",
    columns      => [ 'string1', 'integer1' ],
    sort_columns => [ 'integer1' ],
    sort_order   => [ 'asc' ],
});

my $results = $sheet->content->search(view => $view);

is $results->csv_header, "ID,string1,integer1\n";

my $i;
while (my $line = $results->csv_line)
{
    $i++;
    is $line, "$i,foobar,$i\n";

    # Add a record part way through the download - this should have no impact
    # on the download currently in progress
    if($i == 500)
    {   my $data = { string1 => 'FOOBAR', integer1 => 800 };
        $sheet->content->row_create({ revision => $data })
    }
}

done_testing;
