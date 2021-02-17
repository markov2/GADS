# rewrite of t/007_curval_order.t
# Check the ordering features of curval searches
use Linkspace::Test
#  not_ready => 'needs use of sheet.sort_column';
;

my $curval_sheet = make_sheet rows => [
    { string1 => 'foo1' },
    { string1 => 'foo3' },
    { string1 => 'foo2' },
    { string1 => 'foo4' },
];

my $sheet   = make_sheet
    rows               => [ { string1 => 'foo', curval1 => $curval_sheet->content->row_ids } ],
    columns            => [ qw/string curval/ ],
    multivalue_columns => [ qw/curval/ ],
    curval_column      => $curval_sheet->layout->column('string1');

my @orders =
  ( [ asc  => "foo1 foo2 foo3 foo4" ]
  , [ desc => "foo4 foo3 foo2 foo1" ]
  );

foreach (@orders)
{   my ($order, $expect) = @$_;

    $::session->site->document->sheet_update($curval_sheet,
        { sort_column => 'string1', sort_type => $order });

    like logline, qr/^info: Instance .* changed fields: sort_layout_id sort_type$/,
        "Sorting string1 $order";

    my $row1   = $sheet->row_at(1);
    my $cell1 = $row1->current->cell('curval1');
    ok defined $cell1, "... curval1 of first row";

    # Curval is a multivalue with 4 rows
    my $datums = $cell1->datums;
    cmp_ok @$datums, '==', 4, '... datums';
    ok $_->isa('Linkspace::Datum::Curval'), '... ... all are curval'
         for @$datums;

    my $derefs = $cell1->derefs;
    cmp_ok @$derefs, '==', 4, '... derefs';
    ok ! $_->isa('Linkspace::Datum::Curval'), '... ... none is curval'
         for @$derefs;

    is "@$derefs", $expect, "... curvals in sort order";
    is $cell1->as_string, $expect =~ s/ /, /gr, "... as string";
}

done_testing;
