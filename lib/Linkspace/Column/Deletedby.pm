## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Deletedby;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Column::Person';

###
### META
###

__PACKAGE__->register_type;

sub is_hidden    { 1 }
sub is_internal_type { 1 }
sub is_userinput { 0 }
sub sprefix      { 'current' }
sub tjoin        { 'deletedby' }
sub value_field  { 'deletedby' }
sub value_table  { 'Current' }

###
### Class
###

###
### Instance
###


1;
