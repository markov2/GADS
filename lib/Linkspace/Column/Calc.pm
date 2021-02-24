## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Calc;

use Log::Report 'linkspace';
use Scalar::Util qw(looks_like_number);
use List::Util   qw(first);

use Linkspace::Column::Code::Countries qw(is_country);

use Moo;
extends 'Linkspace::Column::Code';

### 2021-02-22: columns in GADS::Schema::Result::Calc
# id             code           layout_id
# calc           decimal_places return_format

### 2021-02-22: columns in GADS::Schema::Result::Calcval
# id            record_id     value_int     value_text
# layout_id     value_date    value_numeric

###
### META
#
# There should have been many different Calc extensions, but these
# has been folded hacking the meta-data

__PACKAGE__->register_type;

sub can_multivalue { 1 }
sub form_extras  { [ qw/code_calc return_type/ ], [] }
sub has_filter_typeahead { $_[0]->return_type eq 'string' }
sub is_numeric() { my $rt = $_[0]->return_type; $rt eq 'integer' || $rt eq 'numeric' }
sub value_table  { 'Calcval' }

# Use an other field to store the error codes for the lua run, which may be discovered
# later.  We do not want to rerun expressions which cause failures.
#XXX could better be in a separate column.
sub error_field  { $_[0]->return_type eq 'integer' ? 'value_numeric' : 'value_int' }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Calc    => { layout_id => $col_id });
    $::db->delete(Calcval => { layout_id => $col_id });
}

sub _validate($)
{   my ($thing, $update) = @_;

    my $rt = $update->{return_type} // 'string';
    $rt =~ m/^(?:date|numeric|integer|string)$/
         or error __x"Unsupported return type '{rt}' for calc column", rt => $rt;

    my $decimals = $update->{decimal_places} || 0;
    $decimals =~ /^[0-9]+$/
        or error __x"Calc decimal places must be an integer, not '{dp}'", dp => $decimals;

    $thing->SUPER::_validate($update);
    $update;
}

sub _column_extra_update($)
{   my ($self, $extras) = @_;
    keys %$extras or return;

    my $col_id = $self->id;
    $::db->create(Calc => { layout_id => $col_id, %$extras})
        or $::db->update(Calc => { layout_id => $col_id }, $extras);

    $self->update_dependencies;

    # Remove all pre-calculated values: they will get updated on-demand, or
    # with the batch jobs (linkspace code refresh).  Whatever comes first.
    $::db->delete(Calcval => { layout_id => $col_id });

    $self;
}

###
### Instance
###

sub is_valid_value
{   my ($self, $value) = @_;
    my $rt = $self->return_type;
      $rt eq 'date'    ? ($self->parse_date($value) ? $value : undef)
    : $rt eq 'integer' ? ($value =~ /^\s*([-+]?[0-9]+)\s*$/ ? $1 : undef)
    : $rt eq 'numeric' ? (looks_like_number($value) ? $value : undef)
    :                    $value;  # text
}

my %format2field = (
   date    => 'value_date',
   integer => 'value_int',
   numeric => 'value_numeric',
);

sub value_field()  { $format2field{$_[0]->return_type} || 'value_text' }
sub string_storage { $_[0]->value_field eq 'value_text' }

### The "Calc" table

has _calc => (
    is      => 'lazy',
    builder => sub { $::db->get_record(Calc => { layout_id => $_[0]->id }) },
);

sub code           { $_[0]->_calc->{code} }
sub decimal_places { $_[0]->_calc->{decimal_places} // 0 }
sub return_type    { $_[0]->_calc->{return_type} }

sub collect_form($$$)
{   my ($class, $old, $sheet, $params) = @_;
    my $changes = $class->SUPER::collect_form($old, $sheet, $params);
    my $extra = $changes->{extras};
    $extra->{code}      = delete $extra->{code_calc};
    $extra->{no_alerts} = delete $extra->{no_alerts_calc};
    $changes;
}

sub format_value($)
{   my ($self, $value) = @_;
    my $rt   = $self->return_type;

      $rt eq 'date'    ? $::session->site->dt2local($value)
    : $rt eq 'numeric' ? sprintf("%.*f", $self->decimal_places, $value)+0
    : $rt eq 'integer' ? int($value // 0) + 0   # remove trailing zeros
    : defined $value   ? "$value" : undef;

}

sub resultset_for_values
{   my $self = shift;
    $self->value_field eq 'value_text' or return;
    $::db->(Calcval => { layout_id => $self->id }, { group_by  => 'me.value_text' });
}

sub export_hash
{   my $self = shift;
    $self->SUPER::export_hash(@_,
       code           => $self->code,
       return_type    => $self->return_type,
       decimal_places => $self->decimal_places,
    );
}

1;
