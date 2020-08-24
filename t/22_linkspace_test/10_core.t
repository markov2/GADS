
# Check that the Test object loads stuff in this namespace

use Linkspace::Test start_test_session => 0;

ok exists $INC{'warnings.pm'}, 'use warnings';     # may already be on before
ok exists $INC{'strict.pm'}, 'use strict';         # may already be on before

ok exists $INC{'Test/More.pm'}, 'use Test::More';  # otherwise this script wouldnt work

isa_ok $::linkspace, 'Linkspace';
isa_ok $::db,        'Linkspace::DB';
isa_ok $::session,   'Linkspace::Session';
isa_ok $::session,   'Linkspace::Session::System';

done_testing;
