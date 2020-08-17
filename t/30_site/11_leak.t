# Test Site isolation
# Was t/016_site.t

use Linkspace::Test;

#XXX
# Don't create users, as the normal find_or_create check won't find the
# existing user at that ID due to the site_id constraint and will then fail

my $site1  = test_site;
my $sheet1 = test_sheet with_columns => 1;

my $site2  = make_site '2';
my $sheet2 = make_sheet '2', site => $site2, with_columns => 1,
  current_ids_from => 3; #XXX

### Check site 1 records

my $site1b  = Linkspace::Site->from_id($site1->id);
cmp_ok scalar @{$site1b->all_sheets}, '==', 1, 'no leak sheets';
my $sheet1b = $site1b->sheet($sheet1->id);

my @current_ids = map $_->current_id, @{$site1->content->rows};
is( "@current_ids", "1 2", "Current IDs correct for site 1" );

# Try and access record from site 2
my $site2b  = Linkspace::Site->from_id($site2->id);
cmp_ok scalar @{$site2b->sheets}, '==', 2, 'no leak sheets';
my $sheet2b = $site2b->sheet($sheet2->id);

is $site1->content->find_current_id(1)->current_id, 1,
   "Retrieved record from same site (1)";

try { $site1->content->find_current_id(3) };
ok( $@, "Failed to retrieve record from other site (2)" );

is $site2->content->count, 2, "Correct number of records in site 2";

my @current_ids2 = map $_->current_id, @{$site2->content->rows};
is "@current_ids2", "3 4", "Current IDs correct for site 2";

# Try and access record from site 1
is $site2->content->find_current_id(3)->current_id, 3,
   "Retrieved record from same site (2)";

try { $site2->content->find_current_id(1) };
ok $@, "Failed to retrieve record from other site (1)";

### Try and access columns between layouts

my $string_site1 = $sheet1->columns->{string1};
ok ! $sheet2->layout->column($string_site1),
    "Failed to access column from other site by object";

ok !$sheet2->layout->column($string_site1->id),
    "Failed to access column from other site by ID";

# And reverse

my $string_site2 = $sheet2->column('string1');

ok !$sheet1->layout->column($string_site2),
   "Failed to access column from other site by object - reverse";

ok !$sheet1->layout->column($string_site2->id),
   "Failed to access column from other site by ID - reverse";

# Then same with short name
ok !$sheet2b->layout->column($string_site1),
   "Failed to access column from other site by short name";

done_testing();
