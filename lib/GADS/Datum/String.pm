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

package GADS::Datum::String;

use HTML::FromText   qw/text2html/;
use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'GADS::Datum';

with 'GADS::Role::Presentation::Datum::String';

after set_value => sub {
    my ($self, $value) = @_;
    my @values = grep defined, ref $value eq 'ARRAY' ? @$value : $value;

    my $clone     = $self->clone;
    my @text_all  = sort @values;
    my $old_texts = $self->text_all;

    # Trim entries, but only if changed. Don't use $changed, as the act of
    # trimming could affect whether a value has changed or not
    my $changed = "@text_all" ne "@$old_texts";
    if($changed)
    {   s/\h+$// for @values;
    }

    if($changed)
    {   $self->changed(1);
        $self->_set_values(\@values);
        $self->_set_text_all(\@text_all);
    }

    $self->oldvalue($clone);
};

has values => (
    is        => 'rwp',
    isa       => ArrayRef,
    lazy      => 1,
    builder   => sub {
        my $self = shift;
        $self->has_init_value or return [];
        my @values = map { ref $_ eq 'HASH' ? $_->{value} : $_ } @{$self->init_value};
        $self->has_value(@values || $self->init_no_value);
        \@values;
    },
);

# By default we return empty strings. These make their way to grouped
# display as the value to filter for, so this ensures that something
# like "undef" doesn't display
sub html_form  { [ map $_ // '', @{$_[0]->values} ] }
sub text_all   { [ sort @{$_[0]->html_form} ] }
sub is_blank   { ! grep length, @{$_[0]->values} }

sub as_string  { join ', ', @{$_[0]->text_all} }
sub as_integer { panic "Not implemented" }

around 'clone' => sub {
    my $orig = shift;
    my $self = shift;
    $orig->($self, values => $self->values, text_all => $self->text_all, @_);
};

sub html_withlinks
{   my $string = shift->as_string;
    text2html($string, urls => 1, email => 1, metachars => 1);
}

sub _build_for_code
{   my ($self, %options) = @_;

    # Consistently return undef for empty string, so that the variable can be
    # tested in Lua easily using "if variable", otherwise empty strings are
    # treated as true in Lua
    my @values = map length $_ ? $_ : undef, @{$self->text_all};
    $self->column->is_multivalue || @values > 1 ? \@values : $values[0];
}

1;

