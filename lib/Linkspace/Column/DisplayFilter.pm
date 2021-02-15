## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::DisplayFilter;

use Log::Report   'linkspace';
use Linkspace::Util qw(to_id);
use List::Util      qw(first);

use Moo;

# Included below in this file.
my $rule_class = 'Linkspace::Column::DisplayFilter::Rule';

=head1 DESCRIPTION
Select which fields are to be shown.

Room for improvement: most columns will not have a DisplayFilter.  We now look them up
for each column anyway.  Seperately.  The definedness of 'filter_condition' can be used
to flag whether there is a file. Probably requires conversion of existing instances.

=head1 METHODS: Constructors

The display filter is created via C<$layout> methods C<column_create()>
or C<column_update()>, with parameters C<display_filter> and C<display_condition>.
The I<filter> can be specified as L<Linkspace::Column::DisplayFilter>-object,
a single rule-HASH, or an ARRAY of rule-HASHes.

Each rule-HASH contains C<monitor> (a column as id, name_short or object),
C<operator> (C<equal>, C<not_equal>, C<contains> [default], C<not_contains>),
and a C<value> (a blank or undef means "missing").
=cut

#!!! There is no update: we always totally reconstruct the filter on changes
sub _create($$)
{   my ($thing, $column, $rules) = @_;
    my $col_id = to_id $column;
    $rules   ||= [];

    my @rules  = ref $rules eq 'HASH' ? $rules : @$rules;

    $rule_class->cleanup($column);

    foreach my $rule (@rules)
    {   my $monitor = $column->layout->column($rule->{id} || $rule->{monitor})
            or panic $rule->{id} || $rule->{monitor};

        $monitor->id != $col_id
            or error __x"Display filter rules cannot include column itself, in {col.name}",
               col => $monitor;

        $rule_class->create({
            column         => $col_id,
            monitor_id     => $monitor->id,
            value          => $rule->{value}    // '',
            operator       => $rule->{operator} // 'contains',
        }, lazy => 1);
    }

    $thing->from_column($column);
}

sub from_column($)
{   my ($class, $column) = @_;
    $class->new(
        on_column => $column,
        condition => $column->display_condition || 'AND',
    );
}

#----------------------
=head1 METHODS: Accessors
=cut

has on_column => ( is => 'ro', required => 1, weakref  => 1); # 'column()' has global meaning
has condition => ( is => 'ro', default  => 'AND');

has _rule_rows => (
    is      => 'lazy',
    builder => sub { $rule_class->search_objects({ column => shift->on_column }) },
);

sub is_active()   { scalar @{$_[0]->_rule_rows} }

sub monitor_ids() { [ map $_->monitor_id, @{$_[0]->_rule_rows} ] }

#----------------------
=head1 METHODS: Other
=cut

sub as_hash() {
    my $self  = shift;
    my @rules = map +{
        id       => $_->monitor_id,
        operator => $_->operator,
        value    => $_->value,
    }, @{$self->_rule_rows};

    +{  condition => $self->condition,
        rules     => \@rules,
     };
}

sub _show_rule_row {
    my ($self, $rule) = @_;
    join ' ', $rule->monitor->name, $rule->operator, $rule->value;
}

sub summary
{   my $self  = shift;
    my @rules = map $self->_show_rule_row($_), @{$self->_rule_rows};
    my $cond  = $self->condition;

    my $type
      = @rules==1      ? 'Displayed when the following is true'
      : $cond eq 'AND' ? 'Displayed when all the following are true'
      :                  'Displayed when any of the following are true';

    +[ $type, join('; ', @rules) ];
}

sub as_text
{   my $df = $_[0]->summary;
    length $df->[1] ? "$df->[0]: $df->[1]" : '';
}

sub _construct_filter($)
{   my ($self, $sheet) = @_;
    my $rules = $self->_rule_rows;
    @$rules or return sub { 1 };

    my $layout = $sheet->layout;

    my @checks;
    foreach my $rule (@$rules)
    {   my $op     = $rule->operator // panic;
        my $match  = $rule->value    // panic;
        my $other  = $rule->monitor  // panic;

#warn "MATCH($match) $op ", ref $other;
        unless(length $match)
        {   # special case: equal 'blank' means: no values
            return sub {   $_[0]->cell($other)->is_blank } if $op eq 'equal';
            return sub { ! $_[0]->cell($other)->is_blank } if $op eq 'not_equal';
        }

        my $checker
          = $op eq 'equal'        ? sub { !! first { $_ eq  $match   } @{$_[0]} }
          : $op eq 'not_equal'    ? sub {  ! first { $_ eq  $match   } @{$_[0]} }
          : $op eq 'contains'     ? sub { !! first { $_ =~ /$match/ } @{$_[0]} }
          : $op eq 'not_contains' ? sub {  ! first { $_ =~ /$match/ } @{$_[0]} }
          : panic "Unsupported operation '$op'";

        push @checks, sub { $checker->($_[0]->cell($other)->match_values) };
    }

    return $checks[0] if @checks==1;

    $self->condition eq 'AND'
      ? sub { my $rev = $_[0]; ! first { ! $_->($rev) } @checks }
      : sub { my $rev = $_[0];   first {   $_->($rev) } @checks };  # OR
}

sub column_is_selected($)
{   my ($self, $revision) = @_;
    ($self->{LFD_filter} ||= $self->_construct_filter($revision->row->sheet))->($revision);
}

##############
package Linkspace::Column::DisplayFilter::Rule;

use Log::Report   'linkspace';
use Linkspace::Util qw(to_id);

use Moo;
extends 'Linkspace::DB::Table';

### 2020-04-20: columns in GADS::Schema::Result::DisplayField
# id               layout_id        regex
# display_field_id operator

sub db_table { 'DisplayField' }

sub db_field_rename { +{
    display_field_id => 'monitor_id',
    regex            => 'value',
} }

__PACKAGE__->db_accessors;

has monitor => ( is => 'lazy', builder => sub { $_[0]->column($_[0]->monitor_id) } );

sub cleanup($) { $::db->delete($_[0]->db_table => { layout_id => to_id $_[1] } ) }

=head2 my \@column_ids = $class->monitoring($target);
Returns the column_ids which are monitoring the C<$target> column: columns which
have a rule which refer to that target.
=cut

sub monitoring($)
{   my ($self, $target) = @_;
    my $rules = $self->search_objects({monitor => $target});
    [ map $_->column_id, @$rules ];
}

1;
