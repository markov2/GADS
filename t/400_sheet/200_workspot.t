# Test site-managed workspot logic
use Linkspace::Test;

use_ok 'Linkspace::Site';

### Create a site

my $site = Linkspace::Site->site_create({
    hostname => 'test.example.com',
    do_show_title           => 1,
    do_show_organisation    => 1,
    do_show_department      => 1,
    do_show_team            => 1,
    register_freetext1_name => 'Freedom',
    register_freetext2_name => 'Freeze',
});

ok defined $site, 'Created simpelest site, id='.$site->id;
ok logline, "info: Site created ${\$site->id}: test";

### Add definitions

my @deps = qw/dep1 dep2 dep3/;
$site->workspot_create(department => $_) for @deps;
my $deps = $site->departments;
cmp_ok scalar @$deps, '==', scalar @deps, 'Created all departments';
is_deeply [ map $_->name, @$deps ], \@deps, '... same departments';

my @orgs = qw/org1 org2 org3 org4/;
$site->workspot_create(organisation => $_) for @orgs;
my $orgs = $site->organisations;
cmp_ok scalar @$orgs, '==', scalar @orgs, 'Created all organisations';
is_deeply [ map $_->name, @$orgs ], \@orgs, '... same organisations';

my @teams = qw/team1 team2 team3 team4/;
$site->workspot_create(team => $_) for @teams;
my $teams = $site->teams;
cmp_ok scalar @$teams, '==', scalar @teams, 'Created all teams';
is_deeply [ map $_->name, @$teams ], \@teams, '... same teams';

my @titles = qw/title1 title2 title3 title4/;
$site->workspot_create(title => $_) for @titles;
my $titles = $site->titles;
cmp_ok scalar @$titles, '==', scalar @titles, 'Created all titles';
is_deeply [ map $_->name, @$titles ], \@titles, '... same titles';

### Selection

is_deeply $site->workspot_field_titles,
  [ qw/Title Organisation Department Team Freedom Freeze/ ],
  '... column field titles';

is_deeply $site->workspot_field_names,
  [ qw/title organisation department team freetext1 freetext2/ ],
  '... column field names';


### User workspot validation

done_testing;
