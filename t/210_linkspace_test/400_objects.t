# Test the creation of some often used objects

use Linkspace::Test;

### Site

my $site = test_site;
isa_ok $site, 'Linkspace::Site', '...';
is $site->path, 'test-site', '... not the default site';

done_testing;

