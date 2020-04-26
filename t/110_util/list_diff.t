
use Linkspace::Test connect_db => 0;

use Linkspace::Util 'list_diff';

# The order of the returned is HASH-random, to a little organizer to help.
sub list_diff_test($$)
{   my ($from, $to) = @_;
    my ($added, $deleted, $both) = list_diff $from, $to;
    ( [sort @$added], [sort @$deleted], [sort @$both] );
}

is_deeply [ list_diff_test [], [] ],
          [ [], [], [] ],
          'all empty';

is_deeply [ list_diff_test [1..3], [] ],
          [ [], [1..3], [] ],
          'all removed';

is_deeply [ list_diff_test [], [4..6] ],
          [ [4..6], [], [] ],
          'all added';

is_deeply [ list_diff_test [7..9], [7..9] ],
          [ [], [], [7..9] ],
          'all the same';

is_deeply [ list_diff_test [1..6], [4..9] ],
          [ [7..9], [1..3], [4..6] ],
          'overlap';

done_testing;
