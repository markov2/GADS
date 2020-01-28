=pod
GADS - Globally Accessible Data Store
Copyright (C) 2017 Ctrl O Ltd

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

package Linkspace::Filter;

use Encode;
use JSON qw(decode_json encode_json);
use Log::Report 'linkspace';
use MIME::Base64;

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

=head1 NAME

Linkspace::Filter - Generic filter object

=head1 DESCRIPTION
Used by Columns, Views, and DisplayFields.

=head1 METHODS: Constructors

=head2 my $filter = $class->new(%options);
May have C<data>, defaults to empty.  Requires a C<layout>, to resolve
column names.
=cut

has data => (    # private
    is      => 'ro',
    default => sub { +{} },
);

has layout => (  # private
    id      => 'ro',
    required => 1,
);

sub _decode_json_utf8($) { decode_json(encode "utf8", $_[0]) }

=head2 my $filter = $class->from_json($json, %options);
=cut

sub from_json($@)
{   my $class = shift;
    my $data  = _decode_json_utf8(shift || '{}');
    $class->new(data => $data, @_);
}

sub from_hash($@)
{   my ($class, $data) = (shift, shift);
    $class->new(data => $data, @_);
}

sub has_value { !! $_[0]->data }
 
sub base64
{   my $self = shift;

    foreach my $filter (@{$self->filters})
    {   my $col = $layout->column($filter->{column_id})
            or next; # Ignore invalid - possibly since deleted

        if ($col->has_filter_typeahead)
        {
            $filter->{data} = {
                text => $col->filter_value_to_text($filter->{value}),
            };
        }
    }
    # Now the JSON version will be built with the inserted data values
    encode_base64($self->as_json, ''); # Base64 plugin does not like new lines
}

# The IDs of all the columns referred to by this filter
has column_ids => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub { [ map $_->{id}, @{$self->filters} ] },
);

# All the filters in a flat structure
sub _filter_tables($);
has filters => (
    is      => 'lazy',
    builder => sub { [ _filter_tables $_[0] ] },
}

sub _filter_tables
{   my ($self, $filter) = @_;
    if (my $rules = $filter->{rules})
    {   return map _filter_tables $_, @$rules;
    }

    if(my $id = $filter->{id})
    {   # XXX column_id should not really be stored in the hash, as it is
        # temporary but may be written out with the JSON later for permanent
        # use.
        $filter->{column_id} ||= $id =~ /^([0-9])+_([0-9]+)$/ ? $2 : $id;
        return $filter;
    }

    ();
}

# The IDs of the columns that will be subbed into the filter
sub columns_in_subs($)
{   my $self = shift;

    my @colnames = map { $_->{value} && $_->{value} =~ /^\$([_0-9a-z]+)$/i ? $1 : ()}
        @{$self->filters};

    [ grep defined, map $layout->column_by_name_short($_), @colnames ];
}

# Sub into the filter values from a record
sub sub_values
{   my ($self, $layout) = @_;
    my $filter = $self->as_hash;
    # columns_in_subs needs to be built now, otherwise it won't return the
    # correct result once the values have been subbed in below
    my $columns_in_subs = $self->columns_in_subs($layout);

    if (!$layout->record && @$columns_in_subs)
    {
        # If we don't have a record (e.g. from typeahead search) and there
        # are known shortnames in the filter, then don't apply the filter
        # at all (there are no values to substitute in)
        $filter = {};
    }
    else
    {   foreach (@{$filter->{rules}})
        {   $self->_sub_filter_single($_, $layout) or return;
        }
    }
    $self->as_hash($filter);
    $filter;
}

sub _sub_filter_single
{   my ($self, $single, $layout) = @_;
    my $record = $layout->record;
    if ($single->{rules})
    {
        foreach my $rule (@{$single->{rules}})
        {   return 0 unless $self->_sub_filter_single($rule, $layout);
        }
    }
    elsif ($single->{value} && $single->{value} =~ /^\$([_0-9a-z]+)$/i)
    {
        my $col = $layout->column_by_name_short($1);
        if (!$col)
        {   trace "No match for short name $1";
            return 1; # Not a failure, just no match
        }

        my $datum = $record->field($col);

        # First check for multivalue. If it is, we replace the singular rule
        # in this hash with a rule for each value and OR them all together
        if ($col->type eq 'curval')
        {   # Can't really try and match on a text value
            $single->{value} = $datum->ids;
        }
        elsif ($col->multivalue)
        {   $single->{value} = $datum->text_all;
        }
        else
        {   $datum->re_evaluate if !$col->userinput;
            $single->{value} = $col->numeric ? $datum->value : $datum->as_string;
            trace "Value subbed into rule: $single->{value} for column: ".$col->name;
        }
    }
    return 1;
}

sub parse_date_filter
{   my ($class, $value) = @_;

    $value =~ /^(\h*([0-9]+)\h*([+])\h*)?CURDATE(\h*([-+])\h*([0-9]+)\h*)?$/
        or return;

    my $now = DateTime->now;
    my ($v1, $op1, $op2, $v2) = ($2, $3, $5, $6);
    if ($op1 && $op1 eq '+' && $v1) { $now->add(seconds => $v1) }

#   if ($op1 eq '-' && $v1) # Doesn't work, needs coding differently  XXX
#   { $now->subtract(seconds => $v1) }

    if ($op2 && $op2 eq '+' && $v2) { $now->add(seconds => $v2) }
    if ($op2 && $op2 eq '-' && $v2) { $now->subtract(seconds => $v2) }
    $now;
}

sub json()    # returns the json version
{   ...
    return '{}' if @{$self->rules}==0;
}

=head2 my $new = $filter->remove_column($column);
=cut

sub _remove_column_id($$);
sub _remove_column_id($$)
{   my ($h, $col_id) = @_;
    return () if $h->{id}==$col_id;
    my $rules = delete $h->{rules};
    my @new_rules = map _remove_column_id($_, $col_id), @$rules;
    $h->{rules} = \@new_rules if @new_rules;
    $h;
}

sub remove_column($)
{   my ($self, $column) = @_;
    $column or return $self;
    (ref $self)->from_hash(_remove_column_id $self, $column_id);
}

1;
