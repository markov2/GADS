
# Cannot use Linkspace::Test yet
use Test::More;
use warnings;
use strict;

use Linkspace::Util 'scan_for_plugins';

### Find nothing

my $pkg1 = scan_for_plugins MISSING => load => 0;
cmp_ok ref $pkg1, 'eq', 'HASH', "Scanned 'MISSING'";
cmp_ok scalar keys %$pkg1, '==', 0, 'Found nothing';

### Scan, no load

my $pkg2 = scan_for_plugins Command => load => 0;
cmp_ok ref $pkg2, 'eq', 'HASH', "Scanned 'Command' no load";
cmp_ok scalar keys %$pkg2, '>', 0, '... found something';

ok exists $pkg2->{'Linkspace::Command::Show'}, "Found ::Show";
my $fn2 = $pkg2->{'Linkspace::Command::Show'};
ok defined $fn2, '... has filename';
like $fn2, qr/\.pm$/, '... file is pm';
ok -f $fn2, '... file exists';

sub is_loaded($) { my $fn = shift; grep {defined && $_ eq $fn2 } values %INC }

#use Data::Dumper;
#warn Dumper \%INC;
ok ! $INC{'Linkspace/Command/Show.pm'}, '... namespace not loaded';
ok ! is_loaded($fn2), '... pm file not loaded';

### Scan, with load

my $pkg3 = scan_for_plugins Command => load => 1;
cmp_ok ref $pkg3, 'eq', 'HASH', "Scanned 'Command' with load";
cmp_ok scalar keys %$pkg3, '>', 0, '... found something';

ok exists $INC{'Linkspace/Command/Show.pm'}, '... namespace loaded';
ok is_loaded($fn2), '... pm file loaded';

done_testing;
