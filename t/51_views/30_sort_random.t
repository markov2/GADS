# Test random sorting functionality of a view
# Rewrite of t/003_random.t

use Linkspace::Test
    not_ready => 'needs test_sheet simple';

my @data = map +{
    string1 => "Foo $_",
    enum1   => ($_ % 3) + 1,
}, 1..1000;

my $sheet = make_sheet
    columns => [ 'string1', 'enum1' ],
    rows    => \@data;

my $view = $sheet->views->view_create({
    name        => 'Random view',
    columns     => [ 'string1', 'enum1' ],
    sort_column => 'string1',
    sort_order  => 'random',
});

# Retrieve the set of results 10 times, and assume that at some point the
# randomness is such that a different record will be retrieved one of those
# times

my %strings1;
for my $loop (1..10)
{   my $row = $sheet->content->search(view => $view)->row(1);
    $strings1{$row->cell('string1')} = 1;
}

cmp_ok keys %strings1, '>', 1, "More than one different random record";

### Sanity check of normal sort

$sheet->views->view_update($view => {
    sort_column => 'string1',
    sort_order  => 'asc',
});

my %strings2;
for my $loop (1..10)
{   my $row = $sheet->content->search(view => $view)->row(1);
    $strings2{$row->cell('string1')} = 1;
}

cmp_ok keys %strings2, '==', 1, "Same record retrieved for fixed sort";

### Random as second

$sheet->views->view_update($view => {
    sort_column => [ 'enum1', 'string1' ],
    sort_order  => [ 'asc', 'random' ],
});

my (%strings3, %enums3);

for my $loop (1..10)
{   my $row = $sheet->content->search(view => $view)->row(1);
    $strings3{$row->cell('string1')} = 1;
    $enums3{$row->cell('enum1')} = 1;
}

cmp_ok keys %strings3, '>', 1, "Random records retrieved for random part of search";
cmp_ok keys %enums3, '==', 1, "Same record retrieved for fixed part of search";
my $enum = (keys %enums3)[0];
is $enum, "foo1", "Correct sorted value for fixed sort";

done_testing;
