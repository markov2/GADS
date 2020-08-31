use Test::More; # tests => 1;
use strict;
use warnings;
use utf8;

use JSON qw(encode_json);
use Log::Report;

use t::lib::DataSheet;

my @data = (
  { string1    => 'Foo',
    integer1   => '100',
    enum1      => 7,
    tree1      => 10,
    date1      => '2010-10-10',
    daterange1 => ['2000-10-10', '2001-10-10'],
    curval1    => 1,
  },
  { string1    => 'Bar',
    integer1   => '200',
    enum1      => 8,
    tree1      => 11,
    date1      => '2011-10-10',
    daterange1 => ['2000-11-11', '2001-11-11'],
    curval1    => 2,
  },
);

my $curval_sheet = make_sheet '2';

my $sheet   = make_sheet '1',
    data             => $data,
    curval           => $curval_sheet->id,
    curval_field_ids => [ 'string1', 'enum1' ],
);

my $user1 = make_user '1';

#XXX id is hard-coded current_id?
my @tests = (
    { name   => 'enum1',   id => 7, string => 'foo1' },
    { name   => 'tree1',   id => 11, string => 'tree2' },
    { name   => 'person1', id => $user1, string => 'User1, User1' },
    { name   => 'curval1', id => $curval_sheet->id, string => 'Bar, foo2' },
    { name   => 'rag1',    id => 'b_red', string => 'Red' },
);

foreach my $test (@tests)
{   my $col = $layout->column($test->{name});
    ok defined $col, "Test column $test->{name}";
    ok $col->has_fixedvals, '... has fixed values';
    is $col->id_as_string($test->{id}), $test->{string}, '... id string as expected';
    is $col->id_as_string(undef), '', '... undef id string as expected';
}

done_testing;
