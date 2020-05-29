#!/usr/bin/env perl
# Test Linkspace::DB::Table maintainnig a simple list with set_record_list

use Linkspace::Test;

test_session;

### We need to fake some things, to avoid building-up complex data structures
### with code which is not yet available when implementing these tests.

my $sheet = test_sheet;

### Tried to pick a simple table.
### 2020-05-29: columns in GADS::Schema::Result::Topic
# id                    click_to_edit         prevent_edit_topic_id
# instance_id           description
# name                  initial_state
use_ok 'Linkspace::Topic';  # Random simple table

sub get_records() { Linkspace::Topic->search_records({sheet => $sheet}) }
sub set_list(@) { Linkspace::Topic->set_record_list({sheet => $sheet}, @_) }

cmp_ok @{get_records()}, '==', 0, 'Start with empty topic list';

ok ! set_list(undef), 'No list change on undef';
cmp_ok @{get_records()}, '==', 0, '... checked';

my ($add0, $rem0, $ch0) = set_list [];
ok defined $add0, 'Reset empty list to empty';
cmp_ok @$add0, '==', 0, '... no element added';
cmp_ok @$rem0, '==', 0, '... nothing removed';
cmp_ok @$ch0,  '==', 0, '... nothing changed';
cmp_ok @{get_records()}, '==', 0, '... checked';

my ($add1, $rem1, $ch1) = set_list [ { name => 'topic1' } ];
ok defined $add1, 'Add one element';
cmp_ok @$add1, '==', 1, '... one element added';
cmp_ok @$rem1, '==', 0, '... nothing removed';
cmp_ok @$ch1,  '==', 0, '... nothing changed';
is logline, 'info: bulk update Topic table, created 1, removed 0 records';

my $rec1 = get_records;
cmp_ok @$rec1, '==', 1, '... element found in db';
is $rec1->[0]->id, $add1->[0], '... correct element id';
is $rec1->[0]->name, 'topic1', '... correct element name';

my ($add2, $rem2, $ch2) = set_list [];
ok defined $add2, 'Reset empty list to empty';
cmp_ok @$add2, '==', 0, '... no element added';
cmp_ok @$rem2, '==', 1, '... one removed';
cmp_ok @$ch2,  '==', 0, '... nothing changed';
cmp_ok @{get_records()}, '==', 0, '... removed all';
is logline, 'info: bulk update Topic table removed all 1 records';

my ($add3, $rem3, $ch3) = set_list [ { name => 'topic3a' }, { name => 'topic3b' } ];
ok defined $add3, 'Add two elements';
cmp_ok @$add3, '==', 2, '... two element added';
cmp_ok @$rem3, '==', 0, '... nothing removed';
cmp_ok @$ch3,  '==', 0, '... nothing changed';
is logline, 'info: bulk update Topic table, created 2, removed 0 records';
my @rec3 = sort {$a->name cmp $b->name} @{get_records()};
cmp_ok @rec3, '==', 2, '... both element found in db';
is $rec3[0]->id, $add3->[0], '... correct element id';
is $rec3[0]->name, 'topic3a', '... correct element name';
is $rec3[1]->id, $add3->[1], '... correct element id';
is $rec3[1]->name, 'topic3b', '... correct element name';

# No knowledge about equivalence
my ($add4, $rem4, $ch4) = set_list [ { name => 'topic3a' }, { name => 'topic3c' } ];
ok defined $add4, 'Update without equivalence';
cmp_ok @$add4, '==', 2, '... two elements added';
cmp_ok @$rem4, '==', 2, '... two elements removed';
cmp_ok @$ch4,  '==', 0, '... nothing changed';
is logline, 'info: bulk update Topic table, created 2, removed 2 records';

my ($add5, $rem5, $ch5) = set_list [ { name => 'topic3a' }, { name => 'topic3d' } ],
   sub { $_[0]->{name} };
ok defined $add5, 'Update with equivalence';
cmp_ok @$add5, '==', 1, '... one element added';
cmp_ok @$rem5, '==', 1, '... one element removed';
cmp_ok @$ch5,  '==', 0, '... nothing changed';
is logline, 'info: bulk update Topic table, created 1, removed 1, changed 0 records';
my @rec5 = sort {$a->name cmp $b->name} @{get_records()};
cmp_ok @rec5, '==', 2, '... both element found in db';

my ($add6, $rem6, $ch6) = set_list [ { name => 'topic3a', description => 'test change'},
    { name => 'topic3d' } ], sub { $_[0]->{name} };
ok defined $add6, 'Change attribute without replacing whole records';
cmp_ok @$add6, '==', 0, '... no element added';
cmp_ok @$rem6, '==', 0, '... no element removed';
cmp_ok @$ch6,  '==', 1, '... changed one record';
is logline, 'info: bulk update Topic table, created 0, removed 0, changed 1 records';

my @rec6 = sort {$a->name cmp $b->name} @{get_records()};
cmp_ok @rec6, '==', 2, '... both element found in db';
is $rec6[0]->id, $rec5[0]->id, '... correct element id';  #!!! $add5: records not changed
is $rec6[0]->name, 'topic3a', '... correct element name';
is $rec6[0]->description, 'test change', '... correct element description';
is $rec6[1]->id, $rec5[1]->id, '... correct element id';
is $rec6[1]->name, 'topic3d', '... correct element name';

my ($add7, $rem7, $ch7) = set_list [ { name => 'topic3a' } ], sub { $_[0]->{name} };
ok defined $add7, 'Remove one element, keep other unchanged';
cmp_ok @$add7, '==', 0, '... no element added';
cmp_ok @$rem7, '==', 1, '... one element removed';
cmp_ok @$ch7,  '==', 0, '... changed no records';
is logline, 'info: bulk update Topic table, created 0, removed 1, changed 0 records';

my ($add8, $rem8, $ch8) = set_list [];
ok defined $add8, 'Reset list to empty';
cmp_ok @$add8, '==', 0, '... no element added';
cmp_ok @$rem8, '==', 1, '... last element removed';
cmp_ok @$ch8,  '==', 0, '... changed no records';
is logline, 'info: bulk update Topic table removed all 1 records';

done_testing;
