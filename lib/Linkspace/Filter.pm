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
use Scalar::Util qw/blessed/;
use List::Util   qw/first/;

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

=head1 NAME

Linkspace::Filter - Generic filter object

=head1 DESCRIPTION
Used by Columns, Views, and DisplayFields. They behave slightly different.

A column's display-field filter has it's rules in the 'DisplayField' table,
which implies a flat rule-set.

=head1 METHODS: Constructors
=cut

sub _decode_json_utf8($) { decode_json(encode utf8 => $_[0]) }

=head2 my $filter = $class->from_json($json, %options);
Create the filter object from a JSON string.  This is the common format
to store the filter in the database, and (of course) as included in
Ajax calls.
=cut

sub from_json($@)
{   my $class = shift;
    my $data  = _decode_json_utf8(shift || '{}');
    $class->new(_ruleset => $data, @_);
}

=head2 my $filter = $class->from_hash($hash, %options);
A filter based on in-program constructed rules.
=cut

sub from_hash($@)
{   my ($class, $data) = (shift, shift);
    $data && keys %$data or return undef;
    $class->new(_ruleset => $data, @_);
}

=head2 \%h = $filter->as_hash;
Returns the filter rules as HASH.  The internals of the filter are sadly
not cleanly abstracted (but hopefully that will improve)
=cut

sub as_hash() { $_[0]->{_ruleset} }

=head2 my $str = $filter->as_json;
Serialize filter for storage or Ajax.
=cut

sub as_json() { encode_json $_[0]->as_hash }

=head2 my $str = $filter->base64;
Produce a base64 encoded version of the json, to be used in the template
system.  As unexpected side effect, this inserts field texts.
=cut

sub base64
{   my $self   = shift;
    my $layout = $self->sheet->layout;

    foreach my $filter (@{$self->filters})
    {   my $col = $layout->column($filter->{column_id}) or next;
        $filter->{data}{text} = $col->filter_value_to_text($filter->{value})
            if $col && $col->has_filter_typeahead;
    }
    # Now the JSON version will be built with the inserted data values
    encode_base64($self->as_json, ''); # Base64 plugin does not like new lines
}

#------------------------
=head1 METHODS: Filter introspection
=cut

has _ruleset => (
    is      => 'ro',
    default => sub { +{} },
);

=head2 \@ids = $filter->column_ids;
Returns ids for all columns used in the filter rules.
=cut

sub column_ids() { [ map $_->{column_id}, @{$_[0]->filters} ] }

=head2 \@rules = $filter->filters;
Collect all rules recursively.  As side-effect, the C<column_id> gets
extracted from each C<id> attribute in each rule.
=cut

# All the filter rules in a flat structure
sub _filter_tables($);
has filters => (
    is      => 'lazy',
    builder => sub { [ _filter_tables $_[0]->as_hash ] },
);

sub _filter_tables($)
{   my ($filter) = @_;
    if(my $rules = $filter->{rules})
    {   return map +(_filter_tables $_), @$rules;
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

=head2 \@names = $filter->column_names_in_subs;
Returns all column (short) names which are used in the filter, and need
substitution.
=cut

sub column_names_in_subs()
{   my $self = shift;
    [ grep +(defined && /^\$([_0-9a-z]+)$/i ? $1 : undef),
         map $_->{value}, @{$self->filters} ];
}

=head2 my $new_filter = $filter->remove_column($column);
Remove all rules which use the C<$column>.
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
{   my ($self, $which) = @_;
    $which or return $self;
    my $column_id = blessed $which ? $which->id : $which;
    (ref $self)->from_hash(_remove_column_id $self->as_hash, $column_id);
}

=head2 $filter = $filter->renumber_columns(\%mapping);
When a filter gets imported, it contains column numbers from the original
set-up.  Renumber them to numbers used in the new set-up.
=cut

sub renumber_columns($)
{   my ($self, $ext2int) = @_;

    # Update any field IDs contained within a filter
    foreach my $f (@{$self->filters})
    {   $f->{id}    = $ext2int->{$f->{id}}    or panic "Missing ID $f->{id}";
        $f->{field} = $ext2int->{$f->{field}} or panic "Missing field $f->{field}";
        delete $f->{column_id}; # may be present by accident
    }

    $self;
}

=head2 $filter->depends_on_user;
=cut

sub depends_on_user()
{   my $self   = shift;
    my $layout = $self->sheet->layout;

    foreach my $rule (@{$self->filters})
    {   next if +($_->{value} //'') ne '[CURUSER]';

        my $col = $layout->column($_->{column_id});
        return 1 if $col->type eq 'person' || $col->return_type eq 'string';
    }

    0;
}

#---------------
=head1 METHODS: Applying the filter

=head2 \%h = $self->sub_values($row);
Returns a new HASH with the same structure as the filter rules, but then
with the datums filled-in from the C<$row>.  The rules are not evaluated.
=cut

sub sub_values
{   my ($self, $row) = @_;
    $self->_sub_filter_single($self->as_hash, $row);
}

sub _sub_filter_single
{   my($self, $single, $row) = @_;
    my %single = %$single;
    my $layout = $self->sheet->layout;

    if(my $rules = $single{rules})
    {   $single{$rules} = [ map $self->_sub_filter_single($_, $row), @$rules ];
        return \%single;
    }

    my $v = $single->{value};
    if($v && $v =~ /^\$([_0-9a-z]+)$/i && (my $col = $layout->column($1)))
    {   my $datum = $row->field($col);

        if($col->type eq 'curval')
        {   # Can't really try and match on a text value
            $single{value} = $datum->ids;
        }
        elsif($col->is_multivalue)
        {   # Replace the singular rule in this hash with a rule for each value
            # and OR them all together
            $single{value} = $datum->text_all;
        }
        else
        {   $datum->re_evaluate if !$col->userinput;
            $single{value} = $col->is_numeric ? $datum->value : $datum->as_string;
        }
    }
    \%single;
}

=head2 my $date = $filter->parse_date_filter($value);
=cut

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



=head2 $filter->_filter_validate($layout);
=cut

#XXX Only applicable to view filters?
sub _filter_validate($)
{   my ($thing, $layout) = @_;

    # Get all the columns in the filter. Check whether the user has
    # access to them.
    foreach my $filter (@{$self->filters})
    {   my $col_id = $filter->{column_id};
        my $col    = $layout->column($col_id)
            or error __x"Field ID {id} does not exist", id => $col_id;

        my $val   = $filter->{value};
        my $op    = $filter->{operator};
        if($col->return_type eq 'daterange')
        {   # Exact daterange format, than full="yyyy-mm-dd to yyyy-mm-dd"
            my $take = $op eq 'equal' || $op eq 'not_equal' ? 'full_only' : 'single_only';
            $col->validate_search($val, $take => 1);
        }
        elsif($op ne 'is_empty' && $op ne 'is_not_empty')
        {   # 'empty' would normally fail on blank value
            $col->validate_search($val);
        }

        my $has_value = $val && (ref $val ne 'ARRAY' || @$val);
        error __x "No value can be entered for empty and not empty operators"
            if $has_value && ($op eq 'is_empty' || $op eq 'is_not_empty');

        $col->user_can('read')
             or error __x"Invalid field ID {id} in filter", id => $col->id;
    }
}

1;
