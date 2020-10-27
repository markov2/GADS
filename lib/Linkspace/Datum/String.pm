=pod
GADS - Globally Accessible Data Store
Copyright (C) 2014 Ctrl O Ltd

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=cut

package Linkspace::Datum::String;

use warnings;
use strict;

use HTML::FromText   qw/text2html/;
use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Datum';

sub _datum_create($$%)
{   my ($class, $cell, $value) = (shift, shift, shift);
    my $string = ($value->{string} // '') =~ s/\h+/ /gr =~ s/^ //r =~ s/ $//r;
    $value->{value}       = $string;
    $value->{value_index} = lc substr $string, 0, 128;
    $class->SUPER::_datum_create($cell, $value, @_);
}

# By default we return empty strings. These make their way to grouped
# display as the value to filter for, so this ensures that something
# like "undef" doesn't display
sub html_form  { [ map $_ // '', @{$_[0]->values} ] }

sub html_withlinks
{   my $string = $_[0]->as_string;
    text2html $string, urls => 1, email => 1, metachars => 1;
}

# Consistently return undef for empty string, so that the variable can be
# tested in Lua easily using "if variable", otherwise empty strings are
# treated as true in Lua.
sub _value_for_code($$$) { length $_[2] ? $_[2] : undef }

sub presentation($$)
{   my ($self, $cell, $show) = @_;
    $show->{raw}  = my $raw = delete $show->{value};
    $show->{html} = text2html $raw,
        lines     => 1,
        urls      => 1,
        email     => 1,
        metachars => 1;
}

1;

