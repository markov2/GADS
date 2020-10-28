## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

use utf8;
package GADS::Schema::Result::Oauthclient;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components("InflateColumn::DateTime");
__PACKAGE__->table("oauthclient");

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "client_id",
  { data_type => "varchar", is_nullable => 0, size => 64 },
  "client_secret",
  { data_type => "varchar", is_nullable => 0, size => 64 },
);

__PACKAGE__->set_primary_key("id");

1;
