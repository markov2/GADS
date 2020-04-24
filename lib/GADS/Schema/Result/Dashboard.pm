use utf8;
package GADS::Schema::Result::Dashboard;

use strict;
use warnings;

use base 'DBIx::Class::Core';

use JSON qw(decode_json encode_json);

__PACKAGE__->mk_group_accessors('simple' => qw/layout/);

__PACKAGE__->load_components("InflateColumn::DateTime");

__PACKAGE__->table("dashboard");

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "instance_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "user_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
);

__PACKAGE__->set_primary_key("id");

__PACKAGE__->belongs_to(
  "instance",
  "GADS::Schema::Result::Instance",
  { id => "instance_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

__PACKAGE__->belongs_to(
  "user",
  "GADS::Schema::Result::User",
  { id => "user_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

__PACKAGE__->has_many(
  "widgets",
  "GADS::Schema::Result::Widget",
  { "foreign.dashboard_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

1;
