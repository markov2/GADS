package Linkspace::Filter::DisplayField;

use Scalar::Util  qw(blessed);

use Moo;
extends 'Linkspace::Filter';

### 2020-04-20: columns in GADS::Schema::Result::DisplayField
# id               layout_id        regex
# display_field_id operator

# My column is (of course) layout_id.  Refers to display_field_id, which is some
# other column id and see whether it matches regex.

sub from_column($)
{   my ($class, $column) = @_;
    $class->new(column => $column);
}

sub column_id { $_[0]->column->id }
sub condition { $_[0]->column->display_condition || 'AND' }

has column => (
    is       => 'ro'.
    required => 1,
    weakref  => 1,
);

has _rule_rows => (
    is      => 'lazy',
    builder => sub {
        my $col_id = shift->column->id;
        [ $::db->search(DisplayField =>{ layout_id => $col_id)->all ];
  , }
);

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

        (ref $self)->from_hash({
            condition => $self->condition,
            rules     => \@rules,
        });
    },
);

sub summary
{   my $self  = shift;
    my @conds = map $self->_show_rule_row($_), @{$self->_rule_rows};

    my $type = $self->display_condition eq 'AND'
      ? 'Only displayed when all the following are true'
      : $self->display_condition eq 'OR'
      ? 'Only displayed when any of the following are true'
      : 'Displayed when the following is true';

    +[ $type, join('; ', @conds) ];
}

sub as_text
{   my $df = $_[0]->summary || [];
    @$df ? (join ': ', @$df) : '';
}

sub create($$)
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

sub update($)
{   my ($self, $rules) = @_;
    my $col_id = $self->column_id;

    $::db->delete(DisplayField => { layout_id => $col_id });
    $self->create($col_id, $rules);
}

sub show_field($$)
{   my ($self, $row, $datum) = @_;
    my $condition = $self->condition;

    foreach my $rule ($self->_rule_rows)
    {   my $field  = $row->field($rule->display_field_id) or return 1;
        my @values = $field->value_regex_test;

        my $op     = $rule->operator;
        my $regex_string = $rule->regex;
        my $regex  = $op =~ /equal/ ? qr/^${regex_string}$/ : qr/$regex_string/;

        my $this_matches = ! @$values ? 0 : (grep m/$regex/, @values);
        my $want   = $op =~ /not/ ? ! $this_matches : $this_matches;

        if($condition eq 'AND')
        {   return 0 if ! $want;
        }
        else
        {   return 1 if $want;
        }
    }

    0;
}

