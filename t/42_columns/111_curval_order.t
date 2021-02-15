# rewrite of t/007_curval_order.t
# Check the ordering features of curval searches
use Linkspace::Test
    not_ready => 'waiting for curval';

my $curval_sheet = make_sheet rows => [
    { string1 => 'foo1' },
    { string1 => 'foo3' },
    { string1 => 'foo2' },
    { string1 => 'foo4' },
];

my $sheet   = make_sheet
    rows               => [ { string1 => 'foo', curval1 => $curval_sheet->content->row_ids } ],
    columns            => [ qw/string1 curval1/ ],
    multivalue_columns => [ qw/curval1/ ],
    curval_sheet       => $curval_sheet,
    curval_columns     => [ 'string1' ];

my @orders =
  ( [ none => "foo1 foo3 foo2 foo4" ]
  , [ asc  => "foo1 foo2 foo3 foo4" ]
  , [ desc => "foo4 foo3 foo2 foo1" ]
  );

my $row1   = $sheet->content->first_row;
foreach (@orders)
{   my ($order, $expect) = @$_;

    $curval_sheet->sheet_update({ sort_column => 'string1', sort_type => $order });
    ok 1, "Sorting string1 $order";

    # Curval is a multivalue with 4 datums, which each have a value
    my $datums = $row1->cell('curval1')->derefs;

    is "@$datums", $expect, "... curvals in sort order";
    is $row1->cell('curval1'), $expect =~ s/ /, /gr, "... as string";
}

done_testing;
