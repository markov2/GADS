## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Integer;
# Extended by ::Id

use Log::Report 'linkspace';
use Linkspace::Util qw/flat/;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::Column';

my @options = (
    show_calculator => 0,
);

###
### META
###

__PACKAGE__->register_type;

sub datum_class      { 'Linkspace::Datum::Integer' }
sub addable          { 1 }
sub can_multivalue   { 1 }
sub is_numeric       { 1 }
sub option_defaults  { shift->SUPER::option_defaults(@_, @options) }
sub return_type      { 'integer' }
sub value_table      { 'Intgr' }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Intgr => { layout_id => $col_id });
}

###
### Instance
###

sub show_calculator { $_[0]->_options->{show_calculator} }

sub is_valid_value($)
{   my ($self, $value) = @_;
    return $1 if $value =~ /^\s*([+-]?[0-9]+)\s*$/;

    error __x"'{int}' is not a valid integer for '{col}'",
       int => $value, col => $self->name;
}

1;

