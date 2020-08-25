# One row per sheet can be "remembered", which means that is not accepted yet.
# Original test file t/019_remember.t

#XXX Test not yet runnable

use Linkspace::Test;

my $user = test_user;

my %data = (
    string1    => 'Bar',
    integer1   => 99,
    date1      => '2009-01-02',
    enum1      => 'foo1',
    tree1      => 'tree1',
    daterange1 => ['2008-05-04', '2008-07-14'],
    person1    => $user,
);

my $expected = {
    daterange1 => '2008-05-04 to 2008-07-14',
    person1    => $user->fullname,
};

my $sheet = test_sheet rows => 0;

$sheet->content->row_add(\%data, remember => 1);

my $row1 = $sheet->content->row(remembered => 1);

foreach my $c (keys %$data)
{   my $cell     = $row1->cell($col);
    my $field    = $col->name;
    my $expected = $expected->{$field} || $data->{$field};
    is $cell->as_string, $expected, "... column $field";
}

$sheet->content->row_delete($row1);

ok ! defined $sheet->content->row(remembered => 1), 'Cannot load remembered';

done_testing;
