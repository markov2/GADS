# Test integer datums
  
use Linkspace::Test;

my @tests = (
   { value => 42 },
   { value => '43' },
   { value => '  44 ', expect => 44 },
);

my $sheet = make_sheet
    columns => [ 'intgr' ],
    rows    => [ map +{ integer1 => $_->{value} }, @tests ];

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

    my $cell = $rev->cell('integer1');
    ok defined $cell, '... found the cell';

    my $datums = $cell->datums;
    cmp_ok scalar @$datums, '==', 1, '... one datum';
    isa_ok $datums->[0], 'Linkspace::Datum::Integer', '...';

    my $expect = $test->{expect} || $test->{value};
    is $cell->as_string, $expect, '... as string';
    is "$cell", $expect, '... as string, overloaded';

    is $cell->value, $expect, '... as value';
    is_deeply $cell->values, [ $expect ], '... as values';

    is $cell->as_integer, $expect, '... as integer';
}

done_testing;
