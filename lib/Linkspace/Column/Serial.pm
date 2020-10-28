## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Serial;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Column';

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue { 0 }
sub is_internal_type { 1 }
sub is_addable   { 1 }
sub return_type  { 'integer' }
sub is_userinput { 0 }

sub value_table  { 'Current' }
sub value_field  { 'serial' }

###
### Class
###

sub _remove_column($) {}

###
### Instance
###

sub _is_valid_value
{   my ($self, $value) = @_;
    return $1 if $value =~ /^\s*([0-9]+)\s*$/ && $1 != 0;
    error __x"'{serial}' is not a valid Serial", serial => $value;
}

sub sprefix     { 'current' }
sub tjoin       {}
sub is_numeric  { 1 }

1;

