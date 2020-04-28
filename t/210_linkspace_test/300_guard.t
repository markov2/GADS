# Check that tests using Linkspace::Test will restore the database after being run.

use Linkspace::Test;
use Log::Report 'linkspace';

# Use this simple object, which cannot damage much when the test fails.
### 2020-04-28: columns in GADS::Schema::Result::Team
# id         name       site_id

my $site_id = $::session->site->id;

sub get_team { $::db->get_record(Team => { name => 'test' }) }

ok ! get_team, 'No test records in the db (yet)';

my $team_id = $::db->create(Team => { name => 'test' })->id;
ok defined $team_id, "Created team $team_id";

ok get_team, '... found the new record';

ok defined $Linkspace::Test::guard, 'Rollback guard';
$Linkspace::Test::guard->rollback;
ok ! defined $Linkspace::Test::guard, '... removed guard';

ok ! get_team, '... new record disappeared';

done_testing;
