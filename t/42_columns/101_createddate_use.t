# Rewrite t/010_createddate.t
# Tests for timezones of record created dates. The general presumption should
# be that all times are stored in the database as UTC. When they are presented
# to the user, they should be shown in local time (currently only London).

use Linkspace::Test
    not_ready => 'waiting for sheet and calc';

my $sheet   = make_sheet
    rows      => [],
    columns   => [ 'calc1' ],
    calc_code => "function evaluate (_version_datetime)
        return _version_datetime.hour
    end";

### Create the row in Winter Time

set_fixed_time '01/01/2014 12:00:00', '%m/%d/%Y %H:%M:%S';

my $row1    = $sheet->content->row_create;
my $rev11   = $row1->revision_create({ string1 => 'Foobar' });
ok defined $rev11, 'Created new revision';

is $rev11->value('_version_datetime')->hour, 12, '... hour in _version_datetime';
is $rev11->value('_created')->hour, 12, '... hour in _created';
is $rev11->value(calc1 => 0)->hour, 12, '... hour in calc field';
 
### Update the row as if daylight saving time

set_fixed_time '06/01/2014 14:00:00', '%m/%d/%Y %H:%M:%S';  # During Daylight Saving

my $rev12 = $row1->revision_create({ string1 => 'Foobar2' });
ok defined $rev12, 'Created version with different time, say Daylight Saving Time';

is $rev12->value('_version_datetime')->hour, 15, '... hour in _version_datetime';
is $rev12->value('_created')->hour, 12, '... hour in _created';
is $rev12->value(calc1 => 0)->hour, 15, '... hour in calc field';

### Create new row in daylight saving time

set_fixed_time '06/01/2014 16:00:00', '%m/%d/%Y %H:%M:%S';

my $row2  = $sheet->content->row_create;
my $rev21 = $row2->revision_create({ string1 => 'Foobar3' });

is $rev21->value('_version_datetime')->hour, 17, '... hour in _version_datetime';
is $rev21->value('_created')->hour, 17, '... hour in _created';
is $rev21->value(calc1 => 0)->hour, 17, '... hour in calc field';

# Check that the time has been stored in the database as UTC. This is ideally
# to check for a bug that resulted in it being inserted in DST, but
# unfortunately that bug is only exhibited in Pg not SQLite. Tests need to use
# Pg...
#XXX probably not useful anymore: object always constructed from the database
#XXX after construction.
is $::db->get_record(Record => $rev21->id)->created, '2014-06-01T16:00:00',
    "Date insert into database as UTC";

done_testing;
