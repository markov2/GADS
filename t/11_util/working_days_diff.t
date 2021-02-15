# Check the behavior of some date processing functions.  Stolen from t/007_code.t

use Test::MockTime qw/set_fixed_time/; # Load before DateTime
use DateTime;
use Log::Report 'linkspace';

set_fixed_time '10/22/2014 01:00:00', '%m/%d/%Y %H:%M:%S';
my $date = DateTime->now;

use Linkspace::Util qw(working_days_diff working_days_add);

use Test::More;

cmp_ok working_days_diff($date->epoch, 1483488000, 'GB', 'EAW'), '==', 19, 'working_days_diff';

cmp_ok working_days_add($date->epoch, 4, 'GB', 'EAW'), '==', 1428022800, 'working_days_add';

try { working_days_add(2082758400, 1, 'GB', 'EAW') };
like $@->wasFatal->message, qr/No bank holiday information available for year 2036/,
   "Mising bank holiday information warnings for working_days_add";

try { working_days_diff(2051222400, 2051222400, 'GB', 'EAW') };
like $@->wasFatal->message, qr/No bank holiday information available for year 2035/,
    "Missing bank holiday information warnings for working_days_diff";

done_testing;
