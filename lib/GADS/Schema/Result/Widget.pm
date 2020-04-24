use utf8;
package GADS::Schema::Result::Widget;

use strict;
use warnings;

__PACKAGE__->mk_group_accessors('simple' => qw/layout/);

use base 'DBIx::Class::Core';

use JSON qw(decode_json);
use Log::Report 'linkspace';
use MIME::Base64 qw/encode_base64/;
use Session::Token;
use Template;

use JSON qw(decode_json encode_json);

__PACKAGE__->load_components("InflateColumn::DateTime", "+GADS::DBIC");

__PACKAGE__->table("widget");

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "grid_id",
  { data_type => "varchar", is_nullable => 1, size => 64 },
  "dashboard_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "type",
  { data_type => "varchar", is_nullable => 1, size => 16 },
  "title",
  { data_type => "text", is_nullable => 1 },
  "static",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "h",
  { data_type => "smallint", default_value => 0, is_nullable => 1 },
  "w",
  { data_type => "smallint", default_value => 0, is_nullable => 1 },
  "x",
  { data_type => "smallint", default_value => 0, is_nullable => 1 },
  "y",
  { data_type => "smallint", default_value => 0, is_nullable => 1 },
  "content",
  { data_type => "text", is_nullable => 1 },
  "view_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "graph_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "rows",
  { data_type => "integer", is_nullable => 1 },
  "tl_options",
  { data_type => "text", is_nullable => 1 },
  "globe_options",
  { data_type => "text", is_nullable => 1 },
);

__PACKAGE__->set_primary_key("id");

__PACKAGE__->add_unique_constraint("widget_ux_dashboard_grid", ["dashboard_id", "grid_id"]);

__PACKAGE__->belongs_to(
  "dashboard",
  "GADS::Schema::Result::Dashboard",
  { id => "dashboard_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

__PACKAGE__->belongs_to(
  "view",
  "GADS::Schema::Result::View",
  { id => "view_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

__PACKAGE__->belongs_to(
  "graph",
  "GADS::Schema::Result::Graph",
  { id => "graph_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

1;
