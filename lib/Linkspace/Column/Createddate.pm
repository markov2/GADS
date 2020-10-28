## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Createddate;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Column::Date';

###
### META
###

__PACKAGE__->register_type;

sub is_internal_type { 1 }
sub is_userinput     { 0 }

sub value_table  { 'Record' }
sub value_field  { 'created' }
sub tjoin        {}

sub include_time { 1 }

###
### Class
###

sub _remove_column($) {}

###
### Instance
###

sub sprefix      { 'record' }

1;

