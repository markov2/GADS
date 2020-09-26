#!/usr/bin/env perl
# This script creates the test-site, which stays alive until all script
# have run.  See t/99_linkspace_test/10_cleanup.t

use Linkspace::Test
    db_rollback        => 0,
    start_test_session => 0;

my $host = Linkspace::Test::_name_test_site;
if(Linkspace::Site->from_hostname($host))
{   plan skip_all => 'Test site was not cleaned-up: continue with the old object';
}

make_site 0 =>
    hostname => $host;  #XXX no parameters yet, but that may change.

my $site = test_site;
ok defined $site, 'Test site created';
isa_ok $site, 'Linkspace::Site', '... ';

done_testing;
