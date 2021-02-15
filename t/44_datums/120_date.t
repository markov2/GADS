# Test integer datums
  
use Linkspace::Test;

my @tests = (
   { value => '2010-10-10' },
   { value => '2011-11-11' },
   { value => '  2012-12-12 ', expect => '2012-12-12' },
);

my $sheet = make_sheet
    columns => [ 'date' ],
    rows    => [ map +{ date1 => $_->{value} }, @tests ];

ok defined $sheet, 'Create a sheet';
my $content = $sheet->content;

my $row_ids = $content->row_ids;
cmp_ok scalar @$row_ids, '==', scalar @tests, '... found all rows';

foreach my $row_id (@$row_ids)
{   my $test = shift @tests;

    my $row  = $content->row($row_id);
    ok defined $row, "Checking row $row_id, value '$test->{value}'";
    isa_ok $row, 'Linkspace::Row', '...';

    my $rev  = $row->current;
    isa_ok $rev, 'Linkspace::Row::Revision', '...';

    my $cell = $rev->cell('date1');
    ok defined $cell, '... found the cell';

    my $datums = $cell->datums;
    cmp_ok scalar @$datums, '==', 1, '... one datum';
    isa_ok $datums->[0], 'Linkspace::Datum::Date', '...';

    my $expect = $test->{expect} || $test->{value};
    is $cell->as_string, $expect, '... as string';
    is "$cell", $expect, '... as string, overloaded';

    is $cell->value, $expect, '... as value';
    is_deeply $cell->values, [ $expect ], '... as values';
}

done_testing;
