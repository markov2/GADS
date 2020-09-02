# Test Site isolation: no access to sheets or records from other sites.
# Was t/016_site.t

use Linkspace::Test;

plan skip_all => "Needs make_sheet(fill_rows)";

my $site1  = test_site;
my $sheet1 = test_sheet
    fill_rows        => 2;

is $sheet1->site, $site1, 'Sheet1 created in site1';

my $site2  = make_site '2';

my $sheet2 = make_sheet '2',
    site             => $site2,
    fill_rows        => 2,
    current_ids_from => 3;

is $sheet2->site, $site2, 'Sheet2 created in site2';

### Check site1 records

my $site1b  = Linkspace::Site->from_id($site1->id);
cmp_ok @{$site1b->all_sheets}, '==', 1, 'no leak sheets';
my $sheet1b = $site1b->sheet($sheet1->id);

my @current_ids = map $_->current_id, @{$site1->content->rows};
is "@current_ids", "1 2", "Current IDs correct for site 1";

# Try and access record from site2

my $site2b  = Linkspace::Site->from_id($site2->id);
cmp_ok @{$site2b->all_sheets}, '==', 1, 'no leak sheets';

is $sheet1->content->row(1),
   "Retrieved row from same site (1)";

ok ! defined $sheet1->content->row(3),
   "Cannot retrieve to from other site (2)";

is $site2->content->count, 2, "Correct number of records in site 2";

my @current_ids2 = map $_->current_id, @{$site2->content->rows};
is "@current_ids2", "3 4", "Current IDs correct for site 2";

# Try and access record from site 1
ok defined $sheet2->content->row(3),
   "Retrieved tow from same site (2)";

ok ! defined $sheet2->content->row(1),
   "Cannot retrieve row from other site (1)";

### Try and access columns between layouts

my $string_site1 = $sheet1->layout->column('string1');
ok !$sheet2->layout->column($string_site1->id),
    "No access to column from other site by ID";

my $string_site2 = $sheet2->layout->column('string1');
ok !$sheet1->layout->column($string_site2->id),
   "No access to column from other site by ID - reverse";

done_testing;
