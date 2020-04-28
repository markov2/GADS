
# Check that the logging of Linkspace::Test works

use Linkspace::Test;

use Log::Report 'linkspace';

cmp_ok scalar logs(), '==', 0, 'logs are empty';

notice __x"This is a notice";
is +(logs)[0], "notice: This is a notice", 'One notice in logs';
cmp_ok scalar logs(), '==', 0, '... and emptied';

info __x"First info";
info __x"Second info";
cmp_ok scalar logs(), '==', 2, 'Two infos in logs';
cmp_ok scalar logs(), '==', 0, '... and emptied';

#XXX want to test the 'left over log' message, but no idea how
# notice __x"This notice was not handled";

done_testing;
