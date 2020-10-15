# Rewrite from t/007_date.t
# Test filling of date field, the 'default_today' option.

use Linkspace::Test
   not_ready => 'waiting for sheet, simple';

my $sheet   = make_sheet
   columns => [ 'date' ];

my $layout  = $sheet->layout;
my $content = $sheet->content;

$layout->column_update(date1 => { is_optional => 1 });  # just to be sure

# Test default date

my $rev1 = $content->row_create->revision_create;
is $rev1->cell('date1'), '', 'Date blank by default';

# Make date field default to today
set_fixed_time('10/10/2014 01:00:00', '%m/%d/%Y %H:%M:%S');

$layout->column_update(date1 => { default_today => 1 });

my $row2 = $content->row_create;
my $rev2 = $row2->revision_create;
is $rev2->cell('date1'), '2014-10-10', 'Date default to today';

# Write blank value and check it has not defaulted to today
my $rev3 = $row2->revision_create({date1 => ''});
is $rev3->cell('date1'), '', 'Date blank after write';

done_testing;
