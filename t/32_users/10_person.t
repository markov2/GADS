# Test the creations of bare persons: not (yet) with their relations
use Linkspace::Test;

use_ok 'Linkspace::User';
use_ok 'Linkspace::User::Person';
use_ok 'Linkspace::Site::Users';

my $site  = test_site;
is $site->path, 'test-site', '... not the default site';

$site->workspot_create(organisation => 'my orga');
my $orga = $site->workspot(organisation => 'my orga');
ok defined $orga, 'created org "my orga"';

$site->workspot_create(department => 'my dept');
my $dept = $site->workspot(department => 'my dept');

$site->workspot_create(team => 'heroes');
my $team = $site->workspot(team => 'heroes');

$site->workspot_create(title => 'superman');
my $title = $site->workspot(title => 'superman');

### Create session
# We cannot use session->login yet: first need to test that creating
# new users works.

use_ok 'Linkspace::Session';
$::session = Linkspace::Session->new(
    site => $site,
    user => $::session->user,
);
is $::session->site, $site, '... switched session site';

### User manager

my $users = $site->users;
ok defined $users, 'Get Users';
isa_ok $users, 'Linkspace::Site::Users', '...';
is $users->site, $site, '... correct site';

### Create user

my $person = $users->user_create({
    email     => 'test@example.com',
    firstname => 'John',
    surname   => 'Doe',
    organisation => $site->workspot(organisation => 'my orga'),
    department   => $dept,
    team_id      => $team->id,
    title        => $title,
});
ok defined $person, 'Created person '.$person->id;
my $path = $person->path;
is $path, 'test-site/test@example.com', '... path';
is logline, "info: User created ${\$person->id}: $path", '... logged';

isa_ok $person, 'Linkspace::User::Person', '...';
isa_ok $person, 'Linkspace::DB::Table', '...';
isa_ok $person, 'Linkspace::User', '...';

is $person->value, 'Doe, John', '... constructed name';
is $person->session_settings_json, '{}', '... session settings as JSON';
is_deeply $person->session_settings, {},, '... session settings as HASH' ;

is $person->organisation_id, $orga->id, '... found orga';
is $person->department_id, $dept->id, '... found dept';
is $person->team_id, $team->id, '... found team';
is $person->title_id, $title->id, '... found title';

is $person->summary."\n", <<'__SUMMARY', '... summary';
First name: John, Surname: Doe, Email: test@example.com, Title: superman, Organisation: my orga, Department: my dept, Team: heroes
__SUMMARY

### Cached

my $cached = $site->users->user($person->id);
ok defined $cached, 'Get person from cache';
is $cached, $person, '... same object';

ok ! $users->_users_complete, '... admin thinks it is still incomplete';
my $all_users = $users->all_users;
cmp_ok scalar @$all_users, '==', 1, '... there is only one! (administered)';
is $all_users->[0], $person, "... and that's me";
ok $users->_users_complete, '... all_users requested, so now admin complete';

### Update user

$users->user_update($person, {
    firstname => 'Jane',
    team      => undef,
    title_id  => undef,
    session_settings => { tic => 'tac' },
});
is logline, "info: User ${\$person->id}='$path' changed fields: firstname session_settings team_id title value", '... got logged';

is $person->firstname, 'Jane', '... firstname changed';
is $person->value, 'Doe, Jane', '... fullname changed';
ok !defined $person->team_id, '... removed from team';
ok !defined $person->title_id, '... stripped from title';
is $person->department_id, $dept->id, '... kept dept';
is $person->session_settings_json, '{"tic":"tac"}', '... to JSON';

### Update written to disk?

my $clone = Linkspace::User::Person->from_id($person->id);
ok defined $clone, 'Loaded changed clone from DB';
is_deeply $person->session_settings, { tic => 'tac' }, '... restored JSON';
is_deeply $person->{_coldata}, $clone->{_coldata}, '... written';

### Addressed by name

my $clone2 = Linkspace::User::Person->from_name($person->username);
ok defined $clone2, 'Loaded person by name';
is_deeply $person->{_coldata}, $clone2->{_coldata}, '... got same person';

### Person retire

ok ! $person->deleted, 'Person not yet retired';
ok $person->retire, "... retiring";
is logline, "info: User ${\$person->id}='$path' changed fields: deleted lastview";
like $person->deleted, qr/^2\d\d\d-/, '... retired on '.$person->deleted;

### Person delete
ok $users->user_delete($person), '... deleted';
is logline, "info: User ${\$person->id}='$path' changed fields: deleted lastview";
is logline, "info: User ${\$person->id}='$path' deleted";
my $now_missing = Linkspace::User::Person->from_id($person->id);
ok ! defined $now_missing, '... not in table';

done_testing;