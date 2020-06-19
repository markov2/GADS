# Cannot use Linkspace::Test yet
use Test::More;
use warnings;
use strict;

use Linkspace::Util 'flat';

is_deeply [ flat ],
          [ ],
          'no params';

is_deeply [ flat 3 ],
          [ 3 ],
          'one value';

is_deeply [ flat 4..7 ],
          [ 4..7 ],
          'multiple values';

is_deeply [ flat undef, 8, 9, undef, 10, undef ],
          [ 8, 9, 10 ],
          'remove undefs';

is_deeply [ flat [ 11..15 ] ],
          [ 11..15 ],
          'splat array';

is_deeply [ flat [ 16 ], 17, [ 18, 19 ]  ],
          [ 16..19 ],
          'multiple arrays';

is_deeply [ flat [ undef, 20, undef, 21, undef ] ],
          [ undef, 20, undef, 21, undef ],
          'undefs in arrays stay';

done_testing;
