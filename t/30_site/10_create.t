# Test the creation, update and destruction of the contents of sites.
use Linkspace::Test;

use_ok 'Linkspace::Site';

### Create a site
my $host = 'test.example.com';
my $site = Linkspace::Site->site_create({ hostname => $host });

ok defined $site, 'Created simpelest site, id='.$site->id;
isa_ok $site, 'Linkspace::Site', '...';
isa_ok $site, 'Linkspace::DB::Table', '...';
is logline, "info: Site created ${\$site->id}: test";

### Simple attributes

is $site->name, 'test', '... name derived from hostname';
is $site->path, 'test', '... path derived from name';
like $site->created, qr/^2\d\d\d-\d\d-\d\d /, '... created now: '.$site->created;

# Revival via from_id(), from_name(), and from_hostname() already tested
# in db_test/create script.

### export

my $export = $site->export_hash(exclude_undefs => 1, renamed => 1);
#warn Dumper $export;  #XXX visual inspection ;-)
isa_ok $export, 'HASH', 'Can create export';

### All lists

my $sites = $::linkspace->all_sites;
ok defined $site, 'Collect all sites';
cmp_ok $sites, '>=', 2, '... found at least two';
ok scalar (grep $_->hostname eq $host, @$sites), '... found test site';

done_testing;
