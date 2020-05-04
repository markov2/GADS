#!/usr/bin/env perl
use Test::More;
use strict;
use warnings;

use Log::Report;
use Linkspace::Test;
use Linkspace::Util qw/is_valid_id/;

sub _template_user { +{
    surname          => 'Bloggs',
    firstname        => 'Joe',
    email            => 'joe@example.com',
    username         => 'joe@example.com',
    @_,
}; }

my $session = test_session;
my $site    = $session->site;

my $users1  = $site->users;
isa_ok $users1, 'Linkspace::Site::Users', '...';

my $user1   = $users1->user_create(_template_user);
ok defined $user1, 'User created';
isa_ok $user1, 'Linkspace::User', '...';
isa_ok $user1, 'Linkspace::User::Person', '...';

my $user1a  = $users1->user($user1->id);
ok defined $user1a, 'User reloaded from cash';
is $user1a, $user1, '... same object';

$site->refresh('users');
my $users2  = $site->users;
ok defined $users2, 'Reloaded user manager object';
isa_ok $users2, 'Linkspace::Site::Users', '...';
isnt $users1, $users2, '... differs from previous';

my $user1b  = $users2->user($user1->id);
ok $user1b, 'from database';

### test validation

$site->site_update({ register_organisation_mandatory => 1 });

try { $users2->user_create(_template_user email => 'joe1@example.com') };
like $@, qr/Please select a Organisation/, "Failed to create user missing org";
my $org_id = $site->workspot_create(organisation => 'Org');
ok is_valid_id $org_id;

$site->update({ register_team_mandatory => 1 });
try { $users2->user_create(_template_user email => 'joe1@example.com',
    organisation_id => $org_id) };
like $@, qr/Please select a Team/, "missing required team";
my $team_id = $site->workspot_create(team => 'Team');
ok is_valid_id $team_id;

$site->update({ register_department_mandatory => 1 });
try { $users2->user_create(_template_user email => 'joe1@example.com',
    organisation_id => $org_id, team_id => $team_id) };
like $@, qr/Please select a Department/, "missing required department";
my $dept_id = $site->workspot_create(department => 'Dept');
ok is_valid_id $dept_id;

my $user2 = $users2->user_create(_template_user email => 'joe1@example.com',
    organisation_id => $org_id, team_id => $team_id, department_id => $dept_id);
ok $user2, 'Succesfully created user2';
isa_ok $user2, 'Linkspace::User::Person';

logs_purge;
done_testing;
