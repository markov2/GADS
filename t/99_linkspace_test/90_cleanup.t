#!/usr/bin/env perl
# This script removes all testing 

use Linkspace::Test
    db_rollback        => 0,
    start_test_session => 0;   # we kill the info for the test-session

my $site = test_site
    or plan skip_all => "Site already removed";

$site->site_delete;

done_testing;

