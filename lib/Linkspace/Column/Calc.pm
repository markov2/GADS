## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Calc;

use Log::Report 'linkspace';
use Scalar::Util qw(looks_like_number);
use List::Util   qw(first);
use Math::Round  qw(round);

use Linkspace::Column::Code::Countries qw(is_country);

use Moo;
extends 'Linkspace::Column::Code';

### 2021-02-22: columns in GADS::Schema::Result::Calc
# id             code           layout_id
# calc           decimal_places return_format

#XXX calc field is legacy

###
### META
#
# There should have been many different Calc extensions, but these
# has been folded hacking the meta-data

__PACKAGE__->register_type;

sub can_multivalue { 1 }
sub datum_class    { 'Linkspace::Datum::Calc' }
sub form_extras    { [ qw/code return_type decimal_places/ ], [] }
sub has_filter_typeahead { $_[0]->return_type eq 'string' }
sub is_numeric()   { my $rt = $_[0]->return_type; $rt eq 'integer' || $rt eq 'numeric' }
sub value_table    { 'Calcval' }
sub string_storage { $_[0]->value_field eq 'value_text' }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Calc    => { layout_id => $col_id });
    $::db->delete(Calcval => { layout_id => $col_id });
}

my %format2field = (
   date    => 'value_date',
   integer => 'value_int',
   numeric => 'value_numeric',
   string  => 'value_text',
   global  => 'value_text',
   error   => 'value_text',  #XXX ???
);

sub from_record($%)
{   my ($class, $record, %args) = @_;

    my $self = $class->SUPER::from_record($record, %args) or return;

    $self->_set_field_use($self->return_type || 'string')
        unless $args{extras};  # too early when newly created column

    $self;
}

###
### Instance
###

sub value_field(;$) { @_==2 ? $_[0]->{LCC_vf} = $_[1] : $_[0]->{LCC_vf} }
has error_field => ( is => 'rw' );

sub _set_field_use($)
{   my ($self, $format) = @_;
    my $vf = $format2field{$format} or panic $format;
    $self->value_field($vf);
    $self->error_field($vf eq 'value_int' ? 'value_numeric' : 'value_int' );
}

sub _validate($$)
{   my ($thing, $update, $sheet) = @_;

    my $rt = $update->{return_type} // 'string';
    $rt =~ m/^(?:date|numeric|integer|string|globe)$/
         or error __x"Unsupported return type '{rt}' for calc column", rt => $rt;

    my $decimals = $update->{decimal_places} || 0;
    $decimals =~ /^[0-9]+$/
        or error __x"Calc decimal places must be an integer, not '{dp}'", dp => $decimals;

    $thing->SUPER::_validate($update, $sheet);
    $update;
}

sub _column_extra_update($)
{   my ($self, $extras) = @_;

    # May be missing.  For updates, this means: no change.  For inits, which need to set
    # the default to 'string'.  This results in a bit tricky code.
    $extras->{return_format} = delete $extras->{return_type};

    my $rt;
    my $col_id = $self->id;
    if($::db->create(Calc => { layout_id => $col_id, return_format => 'string', %$extras }))
    {   $rt = $extras->{return_format} || 'string';
    }
    else
    {   $::db->update(Calc => { layout_id => $col_id }, $extras);
        $rt = $extras->{return_format} || $self->return_format;
        delete $self->{LCC_rec};
    }

    $self->_set_field_use($rt);

    $self->update_dependencies;

    # Remove all pre-calculated values: they will get updated on-demand, or
    # with the batch jobs (linkspace code refresh).  Whatever comes first.
    $::db->delete(Calcval => { layout_id => $col_id });

    $self;
}

sub is_valid_value
{   my ($self, $value) = @_;
    my $rt = $self->return_type;

    if($rt eq 'date')
    {   return $value if blessed $value && $value->isa('DateTime');

        if(looks_like_number $value)
        {   my $date = try { DateTime->from_epoch(epoch => $value) };
            if($@->died)
            {   warning "$@";
                return ();
            }
            # Database only stores date part, so ensure local value reflects that
            $date->truncate(to => 'day');
            return $date;
        }
        return $self->parse_date($value);
    }
    elsif($rt eq 'numeric')
    {   return $value if looks_like_number $value;
    }
    elsif($rt eq 'integer')
    {   return round $value if looks_like_number $value;
    }
    elsif($rt eq 'globe')
    {   return $value if is_country $value;
    }
    else  # text
    {   return $value;
    }

    error __x"Code for {column.name} did not return a {type}, but '{value}'",
        column => $self, type => $rt, value => $value;
}

### The "Calc" table

sub _calc() { $_[0]->{LCC_rec} ||= $::db->get_record(Calc => { layout_id => $_[0]->id }) }
sub code           { $_[0]->_calc->code }
sub decimal_places { $_[0]->_calc->decimal_places // 0 }
sub return_type    {
$_[0]->_calc or panic;
   $_[0]->_calc->return_format }

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
#XXX
    $::db->search(Calcval => { layout_id => $self->id }, { group_by  => 'me.value_text' });
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
