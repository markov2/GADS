# Test Linkspace::DB::Table accessor creation;

###
### Helper package (based on the complex 'Column')
###

package Test::DB::Table;

use Linkspace::DB::Table;
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::DB::Table';

sub db_table { 'Layout' }

sub db_field_rename { +{
    display_field => 'display_field_old',    # set aside
    internal      => 'is_internal',          # boolean
    isunique      => 'is_unique',            # boolean
}; }

sub db_fields_unused { [ qw/display_matchtype/ ] }

__PACKAGE__->db_accessors;

###
### The real work
###

package main;

use Linkspace::Test;
use Log::Report;

my $record = GADS::Schema::Result::Layout->new({
   name     => 'my name',
   isunique => 1,
   internal => 0,
});

my $object = Test::DB::Table->from_record($record);
isa_ok $object, 'Test::DB::Table';

is $object->db_table, 'Layout', 'Right table';

### simpelest accessor: no name-change

is $object->name, 'my name', 'Attribute not renamed';
try { my $c = $object->name('change') };
ok defined $@, '... cannot change';
like $@->wasFatal->message, qr/^Read-only accessor/, '... expected error';

### use of renamed method

is $object->is_unique, 1, 'Renamed method true';
is $object->is_internal, 0, 'Renamed method false';

### unused database fields

try { my $d = $object->display_matchtype };
ok defined $@, 'Unused table column';
like $@->wasFatal->message, qr/^Field .* not expected/, '... expected error';

### use of old name

try { my $d = $object->isunique };
ok defined $@, 'Use of old column name';
like $@->wasFatal->message, qr/^Accessor .* renamed to/, '... expected error';

done_testing;

