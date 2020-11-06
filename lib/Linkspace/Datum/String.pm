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

sub db_table { 'String' }

has value_index => ( is => 'ro' );

sub _unpack_values($$$%)
{   my ($class, $column, $old_datums, $values, %args) = @_;
    my @strings;
    foreach (grep defined, @$values)
    {   s/\h+/ /g;
        s/^ //;
        s/ $//;
        push @strings, $_ if length;
    }
    \@strings;
}

sub _create_insert(%)
{   my $self  = shift;
    $self->SUPER::_create_insert(@_, value_index => lc(substr $self->value, 0, 128));
}

sub html_withlinks
{   text2html $_[0]->as_string, urls => 1, email => 1, metachars => 1;
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

