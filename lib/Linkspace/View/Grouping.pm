## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::View::Grouping;

use Moo;
extends 'Linkspace::DB::Table';

sub db_table { 'ViewGroup' }
sub path() { $_[0]->view->path . '/' . $_[0]->column->short_name }

### 2020-05-09: columns in GADS::Schema::Result::ViewGroup
# id         layout_id  order      parent_id  view_id

has view => (
    is       => 'ro',
    weakref  => 1,
    required => 1,
);

1;
