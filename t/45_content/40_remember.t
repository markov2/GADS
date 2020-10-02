# One row per sheet can be "remembered", which means that is not accepted yet.
# Original test file t/019_remember.t

use Linkspace::Test
    not_ready => 'wait for draft create support';

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

my $sheet   = make_sheet rows => [];
my $content = $sheet->content;

$content->row_create(\%data, remember => 1);    #XXX draft_create

my $row1 = $content->row(remembered => 1);      #XXX draft_row($user)

foreach my $colname (keys %data)
{   my $cell     = $row1->cell($colname);
    my $field    = $cell->column->name;
    my $expected = $expected->{$field} || $data{$field};
    is $cell->as_string, $expected, "... column $field";
}

$content->row_delete($row1);

ok ! defined $content->row(remembered => 1), 'Cannot load remembered';

done_testing;
