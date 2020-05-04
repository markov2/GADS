# Test configuring the core object

# Do not use Linkspace::Test yet, because we are testing its
# fundamentals.

use Test::More;
use warnings;
use strict;

use_ok 'Linkspace', 'loaded core module';

our $linkspace;

my $l = Linkspace->new;

ok defined $l, 'Created core Linkspace object';
isa_ok $l, 'Linkspace';

is $l, $::linkspace, 'Globally set-up';

cmp_ok ref $l->settings, 'eq', 'HASH', 'config parsed to hash';
is $l->settings->{environment}, 'testing', 'config has facts';
is $l->environment, 'testing', 'use testing rules';

done_testing;

