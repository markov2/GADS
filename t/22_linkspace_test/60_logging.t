
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

info "info 42";
info "info 43";
info "info 44";
is logline, 'info: info 42', 'Pull line by line';
is logline, 'info: info 43', '... second line';
cmp_ok scalar logs(), '==', 1, '... remainder';
ok !defined logline, '... nothing more';

#XXX want to test the 'left over log' message, but no idea how
# notice __x"This notice was not handled";

done_testing;
