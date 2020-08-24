# Test the loading of the Permission table

use Linkspace::Test;

my $session = test_session;
my $user1   = $session->user;

my $users   = $session->site->users;
ok defined $users, 'Get site users';

### The Permission table

my $superid = $users->_global_perm2id('superadmin');
ok defined $superid, "Load id for superadmin=$superid";
is $users->_global_permid2name($superid), 'superadmin', '... reverse also ok';

ok ! defined $users->_global_perm2id('missing'), 'Permission name does not exist';
ok ! defined $users->_global_permid2name(-1), 'Permission id does not exist';

### all

my $a1 = $users->global_permissions;
ok defined $a1, 'Collect all permissions';
cmp_ok scalar @$a1, '>=', 3, '... total '.@$a1;   # There have been more

###
### Now for a users
###

### create permission

my $user2 = make_user '2';
ok defined $user2, 'New user';
ok ! $user2->has_permission('superadmin'), '... is not superadmin';
ok ! $user2->is_admin, '... no, not admin';

$session->user_login($user2);
is logline, "info: login_success Successful login ${\$user2->username} by admin ${\$user1->username}",
    'Loging user with little power';
like logline, qr/^info: User .* changed fields: fail/, '... login success';

try { $user2->add_permission('superadmin') };
like $@->wasFatal->message, qr/not have permission/, '... test user has no permission';

$session->user_logout;  # switch back to system user
is logline, 'info: logout Logging-out', '... logging logout';

ok $user2->add_permission('superadmin'), '... now becomes admin';
is logline, "info: User ${\$user2->path} add permission 'superadmin'", '... logged';

ok $user2->has_permission('superadmin'), '... is superadmin';
ok $user2->is_admin, '... is_admin';
is_deeply $user2->permissions, [ 'superadmin' ], '... list all perms (one)';

ok $user2->add_permission('superadmin'), '... add again, no error no logging';

### remove permission

ok $user2->remove_permission('superadmin'), 'Removing permission';
is logline, "info: User ${\$user2->path} remove permission 'superadmin'", '... logged';
ok ! $user2->has_permission('superadmin'), '... is not superadmin anymore';
ok ! $user2->is_admin, '... no, not admin anymore';
ok ! $user2->remove_permission('superadmin'), '... remove again, no error no logging';
is_deeply $user2->permissions, [ ], '... list all perms (none)';

done_testing;
