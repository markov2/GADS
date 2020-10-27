## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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

