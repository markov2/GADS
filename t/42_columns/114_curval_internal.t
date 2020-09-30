# Rewrite of t/007_curval_internal.t
# Tests to check that internal columns can be used in curval fields

use Linkspace::Test
    not_ready => 'waiting for curval';

my $curval_sheet = make_sheet 2,
    rows               => [ { string1 => 'foo1' } ],
    columns            => [ 'string1' ];

my $sheet   = make_sheet 1,
    rows               => [ { string1 => 'foo', curval1 => 1 } ],
    columns            => [ qw/string1 curval1/ ],
    curval_sheet       => $curval_sheet,
    curval_offset      => 6,
    curval_columns     => [ qw/string1 _serial _id/ ];

my $row = $sheet->content->row(2);
is $row->cell('curval1'), '1, 1, foo1', 'Curval with ID correct';

done_testing;
