package Linkspace::Filter::DisplayField;

use Scalar::Util  qw(blessed);

use Moo;
extends 'Linkspace::Filter';

### This is a display_field filter management object, so does not extend from
#   Linkspace::DB::Table

### 2020-04-20: columns in GADS::Schema::Result::DisplayField
# id               layout_id        regex
# display_field_id operator

# My column is (of course) layout_id.  Refers to display_field_id, which is some
# other column id and see whether it matches regex.

my %operators = (   # fixed_regex, negate
    equal        => [ 1, 0 ],
    contains     => [ 0, 0 ],
    not_equal    => [ 1, 1 ],
    not_contains => [ 0, 1 ],
);

sub from_column($)
{   my ($class, $column) = @_;
    $class->new(
        on_column => $column,
        condition => $column->display_condition,
    );
}

sub on_column_id { $_[0]->on_column->id }

has on_column => (     # method 'column' has global meaning
    is       => 'ro'.
    required => 1,
    weakref  => 1,
);

has condition => (
    is       => 'ro',
    default  => sub { 'AND' },
);

has _rule_rows => (
    is      => 'lazy',
    builder => sub {
        my $col_id = shift->on_column->id;
        [ $::db->search(DisplayField => { layout_id => $col_id})->all ];
  , }
);

#XXX Maybe store layout?
sub column($) { $_[0]->on_column->layout->column($_[1]) }

sub _show_rule_row {
    my ($self, $rule) = @_;
    join ' ',
        $self->column($rule->display_field_id)->name,
        $rule->operator,
        $rule->regex;
}

has as_hash => (
    is      => 'lazy',
    builder => sub { +{
        my $self  = shift;
        my @rules = map +{
            id       => $_->display_field_id,
            operator => $_->operator,
            value    => $_->regex,
        }, @{$self->_rule_rows};

        +{  condition => $self->condition,
            rules     => \@rules,
         };
    },
);

sub summary
{   my $self  = shift;
    my @rules = map $self->_show_rule_row($_), @{$self->_rule_rows};
    my $cond  = $self->display_condition;

    my $type
      = @rules==1    ? 'Displayed when the following is true'
      : $dc eq 'AND' ? 'Displayed when all the following are true'
      :                'Displayed when any of the following are true';

    +[ $type, join('; ', @rules) ];
}

sub as_text
{   my $df = $_[0]->summary || [];
    @$df ? (join ': ', @$df) : '';
}

sub filter_create($$)
{   my ($thing, $where, $rules) = @_;
    my $col_id = blessed $where ? $where->id : $where;

    foreach my $cond (@$rules)
    {
        $cond->{column_id} != $col_id
            or error __"Display condition field cannot be the same as the field itself";

        $::db->create(DisplayField => {
            layout_id        => $col_id,
            display_field_id => $cond->{column_id},
            regex            => $cond->{value},
            operator         => $cond->{operator},
        });
    }
}

sub filter_update($)
{   my ($self, $rules) = @_;
    my $col_id = $self->on_column_id;

    $::db->delete(DisplayField => { layout_id => $col_id });
    $self->filter_create($col_id, $rules);
}

sub show_field($$)
{   my ($self, $row, $datum) = @_;
    my $condition = $self->condition;

    foreach my $rule ($self->_rule_rows)
    {   my $field  = $row->field($rule->display_field_id) or return 1;
        my @values = $field->value_regex_test;

        my $op     = $rule->operator;
        my ($fixed, $negate) = @{$operator{$op} or panic};

        my $regex_string = $rule->regex;
        my $regex  = $fixed ? qr/^${regex_string}$/ : qr/$regex_string/;

        my $this_matches = ! @$values ? 0 : (grep m/$regex/, @values);
        my $want   = $negate ? ! $this_matches : $this_matches;

        if($condition eq 'AND')
        {   return 0 if ! $want;
        }
        else
        {   return 1 if $want;
        }
    }

    0;
}

