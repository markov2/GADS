# Rewrite of t/007_curval_internal.t
# Tests to check that internal columns can be used in curval fields

use Linkspace::Test;

my $curval_sheet = make_sheet
    columns        => [ 'string' ],
    rows           => [ { string1 => 'foo1' } ];

my $cur_row1     = $curval_sheet->row_at(1);
my $cur_rev1_id  = $cur_row1->current->id;

my $sheet        = make_sheet
    columns        => [ qw/string curval/ ],
    rows           => [ { string1 => 'foo', curval1 => $cur_row1->id } ],
    curval_columns => [ map $curval_sheet->layout->column($_), qw/string1 _serial _id/ ];

my $row1 = $sheet->row_at(1);
is $row1->current->cell('curval1')->as_string, "$cur_rev1_id, 1, foo1", 'Curval with ID correct';

done_testing;
