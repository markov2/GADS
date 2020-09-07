use Test::More;
use warnings;
use strict;

use Linkspace::Util 'normalize_string';

is normalize_string 'abc', 'abc', 'ident';
is normalize_string '  abc', 'abc', 'leading blanks';
is normalize_string 'abc  ', 'abc', 'trailing blanks';
is normalize_string 'a   b  c', 'a b c', 'multi within';
is normalize_string "  \t a  \tbc  \t", 'a bc', 'complex';

done_testing;
