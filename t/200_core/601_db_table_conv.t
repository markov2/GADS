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

sub db_fields_unused { [ qw/display_matchtype display_regex/ ] }

__PACKAGE__->db_accessors;

package Test::Object;
sub new { bless {}, __PACKAGE__ }
sub id { 42 };

###
### The real work
###

package main;

use Linkspace::Test;
use Log::Report;

my $conv = Test::DB::Table->_record_converter;

### Simple

is_deeply $conv->({name => 'my name'}),
   +{ name => 'my name' },
   'unmodified field';

### Booleans

is_deeply $conv->({ is_internal => 1 }),
   +{ internal => 1 },
   'boolean field, true';

is_deeply $conv->({ is_internal => 0 }),
   +{ internal => 0 },
   'boolean field, false';

is_deeply $conv->({ is_internal => undef }),
   +{ internal => 0 },
   'boolean field, false (undef)';

is_deeply $conv->({ do_remember => 5 }),
   +{ remember => 1 },
   'boolean field, true';

### ID

my $obj = Test::Object->new;

is_deeply $conv->({ link_parent => 43 }),
   +{ link_parent => 43 },
   'id field without _id, pass id';

is_deeply $conv->({ link_parent => $obj }),
   +{ link_parent => 42 },
   'id field without _id, pass object';

is_deeply $conv->({ link_parent_id => 44 }),
   +{ link_parent => 44 },
   'id field with _id, pass id';

### JSON

is_deeply $conv->({ filter => {rules => []} }),
   +{ filter => '{"rules":[]}' },
   'json by HASH, without _json';

is_deeply $conv->({ filter_json => {rules2 => []} }),
   +{ filter => '{"rules2":[]}' },
   'json by HASH, with _json';

is_deeply $conv->({ filter => '{"rules3":[]}' }),
   +{ filter => '{"rules3":[]}' },
   'json by string, without _json';

is_deeply $conv->({ filter_json => '{"rules4":[]}' }),
   +{ filter => '{"rules4":[]}' },
   'json by string, with _json';

is_deeply $conv->({ filter => undef }),
   +{ filter => '{}' },
   'json undef, without _json';

is_deeply $conv->({ filter_json => undef }),
   +{ filter => '{}' },
   'json undef, with _json';

### Use of old name

try { $conv->({isunique => 1}) };
like $@, qr/Old key/, 'key should not be used anymore';

### Unused

try { $conv->({display_matchtype => 4}) };
like $@, qr/unused/, 'field is not in use anymore';

done_testing;
