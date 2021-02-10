## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Id;

use Log::Report 'linkspace';
use Linkspace::Datum::Integer ();

use Moo;
extends 'Linkspace::Column::Intgr';

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue   { 0 }
sub is_internal_type { 1 }
sub is_userinput     { 0 }
sub sprefix          { 'current' }
sub tjoin            {}
sub value_field      { 'id' }
sub value_table      { 'Current' }

###
### Class
###

sub _remove_column($) {}

###
### Instance
###

sub is_valid_value($)
{   my ($self, $value) = @_;
    return $1 if $value =~ /^\s*([0-9]+)\s*$/ && $1 != 0;
    error __x"'{id}' is not a valid ID", id => $value;
}

1;

