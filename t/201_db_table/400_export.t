# Test Linkspace::DB::Table record conversion for create and update

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
    filter        => 'filter_json',
    force_regex   => 'force_regex_string',   
    internal      => 'is_internal',          # boolean
    isunique      => 'is_unique',            # boolean
    link_parent   => 'link_parent_id',       # id
    related_field => 'related_field_id',
    remember      => 'do_remember',
}; }

sub db_fields_unused    { [ qw/display_matchtype display_regex/ ] }
sub db_fields_no_export { [ qw/internal/ ] }

__PACKAGE__->db_accessors;

###
### The real work
###

package main;

use Linkspace::Test;
use Log::Report;

my $record = GADS::Schema::Result::Layout->new({
   display_matchtype => 'ignore',
   filter   => '{}',
   id       => 42,
   internal => 0,
   isunique => 1,
   link_parent => undef,
   name     => 'my name',
   textbox  => undef,
});

my $object = Test::DB::Table->from_record($record);
isa_ok $object, 'Test::DB::Table', 'Created test object';

### Plain

my $h1 = $object->export_hash;
ok defined $h1, 'HASH with original keys';
is_deeply $h1,
 +{ id => 42,
    filter      => '{}',
    isunique    => 1,
    link_parent => undef,
    name        => 'my name',
    textbox     => undef,
  }, '... export original';

### Renamed

my $h2 = $object->export_hash(renamed => 1);
ok defined $h2, 'HASH with renamed keys';
cmp_ok scalar keys %$h1, '==', scalar keys %$h2, '... same size';

is_deeply $h2,
 +{ id => 42,
    filter_json    => '{}',
    is_unique      => 1,
    link_parent_id => undef,
    name           => 'my name',
    textbox        => undef
 }, '... export renamed';

### Only defined

my $h3 = $object->export_hash(exclude_undefs => 1);
ok defined $h3, 'HASH without undefs';
cmp_ok scalar keys %$h3, '<', scalar keys %$h1, '... fewer elements';
is_deeply $h3,
 +{ id => 42,
    filter      => '{}',
    isunique    => 1,
    name        => 'my name',
  }, '... export original only defined';

done_testing;
