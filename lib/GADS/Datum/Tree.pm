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

package GADS::Datum::Tree;

use Log::Report;
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'GADS::Datum';

after set_value => sub {
    my ($self, $value) = @_;
    my $clone = $self->clone; # Copy before changing text
    my @values = sort grep $_, ref $value eq 'ARRAY' ? @$value : ($value);
    my @old    = sort @{$self->ids};
    my $changed = "@values" ne "@old";

    my $column  = $self->column;
    if($changed)
    {   $column->is_valid_value($_, fatal => 1) for @values;
        my @text = map $column->node($_)->{value}, @values;
        $self->text_all(\@text);
    }
    $self->changed($changed);
    $self->oldvalue($clone);
    $self->ids(\@values);
};

sub id { panic "id() removed for Tree datum" }

sub ids           { $_[0]->value_hash->{ids} || [] }
sub ids_as_params { join '&', map "ids=$_", @{$_[0]->ids} }
sub is_blank      { ! grep $_, @{$_[0]->ids} }

# Make up for missing predicated value property
sub has_value     { ! $_[0]->is_blank || $_[0]->init_no_value }
sub html_form     { [ map $_||'', @{$_[0]->ids} ] }

has value_hash => (
    lazy    => 1,
    builder => sub {
        my $self = shift;
        $self->has_init_value or return {};

        my $column = $self->column;

        # XXX - messy to account for different initial values. Can be tidied
        # once we are no longer pre-fetching multiple records

        my @values = map { ref $_ eq 'HASH' && $_->{record_id} ? $_->{value} : $_ } @{$self->init_value};

        my (@ids, @texts);
        foreach (@values)
        {   if(ref $_ eq 'HASH')
            {   next if !$_->{id};
                push @ids,   $_->{id};
                push @texts, $_->{value} || '';
            }
            elsif(my $node = $column->node($_))
            {   push @ids,   $node->{id};
                push @texts, $node->{value};
            }
        }

        +{
            ids  => \@ids,
            text => \@texts,
         };
    },
);


sub ancestors { $_[0]->column->ancestors }

has full_path => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        my @all;
        my @all_texts = @{$self->text_all};
        foreach my $anc (@{$self->ancestors})
        {   my $path = join '#', map $_->{value}, @$anc;
            my $text = shift @all_texts;
            push @all, $path ? "$path#".$text : $text;
        }
        \@all;
    },
);

sub value_regex_test { shift->full_path }
sub as_string  { $_[0]->text // "" }
sub as_integer { panic "No integer value" }

# Internal text, array ref of all individual text values
sub text { join ', ', @{$_[0]->text_all} }
sub text_all { $_[0]->value_hash->{text} || [] }

around 'clone' => sub {
    my $orig = shift;
    my $self = shift;
    $orig->($self,
        ids     => $self->ids,
        text    => $self->text,
        @_,
    );
};

sub _code_values($)
{   my ($self, $column, $node_id) = @_;

    my $node    = $column->node($node_id);
    my @parents = $node ? $node->{node}{node}->ancestors : ();
    pop @parents; # Remove root

    my (%parents, $count);
    foreach my $parent (reverse @parents)
    {   my $pnode_id = $parent->name;  #XXX name or id?
        my $pnode    = $column->node($pnode_id);

        # Use text for the parent number, as this will not work in Lua:
        # value.parents.1
        $parents->{'parent'.++$count} = $pnode->{value};
    }

     +{ value   => $self->is_blank ? undef : $node->{value},
        parents => \%parents,
      };
}

sub _build_for_code
{   my $self   = shift;
    my $column = $self->column;
    my @values = map $self->_code_values($column, $_), @{$self->ids};

    return \@values
       if $column->is_multivalue || @values > 1;

    # If the value is blank then still return a hash. This makes it easier
    # to use in Lua without having to test for the existence of a value
    # first
    $values[0] || +{ value => undef, parents => {} };
}

1;
