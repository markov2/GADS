# Test the creation and update of a site's sheet administration
# other administrative groups)

use Linkspace::Test;

use_ok 'Linkspace::Site::Document';

my $site = test_site;

my $doc  = $site->document;
isa_ok $doc, 'Linkspace::Site::Document';

is $doc->site, $site, 'refers back to site';

is_deeply $doc->all_sheets, [], 'no sheets yet';

is_deeply $doc->columns([]), [], 'get no columns';

done_testing;

