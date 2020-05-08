# Test the loading of the Permission table

use Linkspace::Test;

my $users = test_site->users;
ok defined $users, 'Get site users';

my $superid = $users->_global_perm2id('superadmin');
ok defined $superid, "Load id for superadmin=$superid";
is $users->_global_permid2name($superid), 'superadmin', '... reverse also ok';

ok ! defined $users->_global_perm2id('missing'), 'Permission name does not exist';
ok ! defined $users->_global_permid2name(-1), 'Permission id does not exist';

### all
my $a1 = $users->global_permissions;
ok defined $a1, 'Collect all permissions';
cmp_ok scalar @$a1, '>=', 3, '... total '.@$a1;   # There have been more

done_testing;
