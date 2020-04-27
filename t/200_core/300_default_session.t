# Test configuring the core object

# Do not use Linkspace::Test yet, because we are testing its
# fundamentals.

use warnings;
use strict;

use Log::Report 'linkspace';
use Test::More;
use English qw/$UID/;

use_ok 'Linkspace', 'loaded core module';

our $linkspace = Linkspace->new;
ok defined $linkspace, 'Has linkspace';

our $db = $linkspace->db;
ok defined $db, 'Has database';

# Dispatcher not yet configured
my $disp = dispatcher find => 'default';
isa_ok $disp, 'Log::Report::Dispatcher::Perl';

### Try to get the default site (don't test it)

my $host = $linkspace->settings->{default_site};
ok defined $host, "Load site named $host";

my $site = Linkspace::Site->from_host($host);
ok defined $site, "... collected Site";
isa_ok $site, 'Linkspace::Site';
isa_ok $site, 'Linkspace::DB::Table';
is $site->host, $host, '... right site loaded';

### Try creating a system user

use_ok 'Linkspace::User::System';
my $user = Linkspace::User::System->new;
isa_ok $user, 'Linkspace::User::System';
isa_ok $user, 'Linkspace::User';
ok ! $user->isa('Linkspace::DB::Table'), 'Not a ::DB::Table';

is $user->id, -$UID, 'system users are negative';

### Let's try to start the linkspace process

our $session;
$linkspace->start;

ok defined $session, 'Session started';
ok defined $session->site, '... has site';
is $session->site->id, $site->id, '... default site for session';
ok defined $session->user, '... has user';
is $session->user->id, $user->id, '... system user for session';

my $disp2 = dispatcher find => 'default';
isa_ok $disp2, 'Log::Report::Dispatcher::Syslog';

done_testing;
