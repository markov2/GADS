# Test configuring the core object

# Do not use Linkspace::Test yet, because we are testing its
# fundamentals.

use Test::More;
use warnings;
use strict;

use_ok 'Linkspace', 'loaded core module';

our $linkspace = Linkspace->new;
isa_ok $linkspace, 'Linkspace';

our $db = $linkspace->db;
ok defined $db, 'Created a db';
isa_ok $db, 'Linkspace::DB';

my $schema = $db->schema;
ok defined $schema, 'Got schema';
isa_ok $schema, 'GADS::Schema';

my @sources = $schema->sources;
cmp_ok scalar @sources, '>', 20, 'Found '.@sources.' sources';

ok scalar(grep $_ eq 'Site', @sources), 'Found source Site';

done_testing;

