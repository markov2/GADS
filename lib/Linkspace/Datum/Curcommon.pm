## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Datum::Curcommon;

use Log::Report 'linkspace';
use CGI::Deurl::XS 'parse_query_string';
use HTML::Entities  qw/encode_entities/;
use Scalar::Util    qw/blessed/;
use List::Util      qw/uniq/;

use Linkspace::Util qw/list_diff is_valid_id/;

use Moo;
extends 'Linkspace::Datum';

sub db_table { 'Curval' }

sub values_as_query_records
{   my $self = shift;
    my @rows;
    my $curval_sheet = $self->column->curval_sheet;
    my $accept_input = $curval_sheet->layout->columns_search(user_can_write_new => 1, userinput => 1);

my $row_data;
    while(my ($row_id, $revision_data) = each %$row_data)
    {   my $curval_row = $curval_sheet->content->row($row_id);
        my %revision;
        foreach my $col (@$accept_input)
        {   $revision{$col->name_short} = $revision_data->{$col->field_name};
        }
        #XXX create revision
    }
    ...;
}

sub html_withlinks
{   my $self = shift;
    $self->as_string or return "";
    my @return;
    foreach my $v (@{$self->values})
    {   my $string = encode_entities $v->{value};
        my $link   = "/record/$v->{id}?oi=".$self->related_sheet_id;
        push @return, qq(<a href="$link">$string</a>);
    }
    join '; ', @return;
}

sub set_values  #XXX ???
{   my $self = shift;
    $self->column->value_selector eq 'noshow'
        ? [ map $_->{id}, @{$self->html_form} ]
        : $self->html_form;
}

sub html_form
{   my ($self, $cell) = @_;

    $self->column->value_selector eq 'noshow'
        or return $self->ids;

    my @return;
    foreach my $val (@{$self->values})
    {
        my $record = $val->{record};
        $val->{as_query} = $record->as_query
            if $record->is_draft;

        # New entries may have a current ID from a failed database write, but don't use
        $val->{presentation} = $self->presentation;
        push @return, $val;
    }
    return \@return;
}

sub _values_for_code($$$)
{   my ($self, $cell, $value, $args) = @_;

    # Get all field data in one chunk
    my %options = (
        already_seen_code => $args->{already_seen_code}, 
        level => $args->{already_seen_level},
    );

#XXX rewrite to call for 1
my $field_values;
    my $column = $cell->column;
    $self->_records
        ? $column->field_values_for_code(rows => $self->_records, %options)
        : $column->field_values_for_code(ids => $self->ids, %options);

     +{
        id           => int $value->{id}, # Ensure passed to Lua as number not string
        value        => $value->{value},
        field_values => $field_values->{$value->{id}},
      };
}

sub presentation
{   my ($self, $cell, $show) = @_;

    $show->{text}  = $self->value;
    $show->{links} = [ map +{
        id              => $_->{id},
        href            => $_->{value},
        refers_to_sheet => $cell->column->related_sheet,
        values          => $_->{values},
        presentation    => $cell->revision->presentation(columns => $self->column->curval_columns),
    }, @{$self->values} ];
}

1;
