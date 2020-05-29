
# Cannot use Linkspace::Test yet
use Test::More;
use warnings;
use strict;

use Linkspace::Util 'make_wordlist';

is make_wordlist(), '', 'Empty list';
is make_wordlist('tic'), 'tic', 'One element';
is make_wordlist(qw/tic tac/), 'tic and tac', 'Two elements';
is make_wordlist(qw/tic tac toe/), 'tic, tac and toe', 'More elements';

is make_wordlist( [qw/tic tac toe/ ]), 'tic, tac and toe', 'As an ARRAY';

done_testing;
