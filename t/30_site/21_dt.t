# Test local2dt
use Linkspace::Test;

my $site = test_site;

my $date1 = $site->local2dt(auto => '2020-09-24');
is $date1->stringify, '2020-09-24T00:00:00', 'auto date';
is $site->dt2local($date1), '2020-09-24', '... dt to local';

my $datetime1 = $site->local2dt(auto => '2020-09-23 12:34:56');
is $datetime1->stringify, '2020-09-23T12:34:56', 'auto datetime';
is $site->dt2local($datetime1), '2020-09-23', '... dt to local';
is $site->dt2local($datetime1, include_time => 1), '2020-09-23 12:34', '... dt to local';

is $site->local2dt(date => '2021-09-24')->stringify, '2021-09-24T00:00:00', 'date';
is $site->local2dt(datetime => '2021-09-23 12:34:56')->stringify, '2021-09-23T12:34:56',
    'datetime';

done_testing;
