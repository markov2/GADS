# rewrite of t/007_curval_order.t
# Check the ordering features of curval searches
use Linkspace::Test
    not_ready => 'waiting for curval';

my $curval_sheet = make_sheet 2, rows => [
    { string1 => 'foo1' },
    { string1 => 'foo2' },
    { string1 => 'foo3' },
    { string1 => 'foo4' },
];

my $sheet   = make_sheet 1,
    rows               => [ { string1 => 'foo', curval1 => [ 1..4 ] } ],
    columns            => [ qw/string1 curval1/ ],
    multivalue_columns => [ qw/curval1/ ],
    curval_sheet       => $curval_sheet,
    curval_offset      => 6,
    curval_columns     => [ 'string1' ];

foreach my $order (qw/asc desc/)
{
    $curval_sheet->sheet_update({
        sort_column    => 'string1',
        sort_type      => $order,
    });
    my $expect = $order eq 'asc' ? "foo1 foo2 foo3 foo4" : "foo4 foo3 foo2 foo1";

    my $row1   = $sheet->content->row(5);   #XXX 5 = 4 current_ids in cursheet + 1

    # Curval is a multivalue with 4 datums, which each have a value
    my @cells1 = map $_->value(0), @{$row1->cell('curval1')->values};
    is "@cells1", $expect, "Curvals in correct order for sort $order";

    is $row1->cell('curval1'), $expect =~ s/ /, /gr, "... as string";
}

done_testing;
