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

package Linkspace::Column::String;

use Log::Report 'linkspace';

use Moo;
extends 'Linkspace::Column';

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue      { 1 }
sub db_field_extra_export { [ qw/is_textbox force_regex/ ] }
sub form_extras         { [ qw/is_textbox force_regex/ ], [] }
sub has_multivalue_plus { 1 }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(String => { layout_id => $col_id });
}


###
### Instance
###

sub must_match { my $re = $_[0]->force_regex; $re ? qr/\A${re}\Z/ms : undef }

sub _is_valid_value($)
{   my ($self, $value) = @_;

    my $clean = $self->is_textbox
      ? $value =~ s/\xA0/ /gr =~ s/\A\s*\n//mrs =~ s/\s*\Z/\n/mrs =~ s/\h+$//gmr =~ s/^\n$//r
      : $value =~ s/[\xA0\s]+/ /gr =~ s/^ //r =~ s/ $//r;

    if(my $m = $self->must_match)
    {   # Ugly output when the value is a multiline
        $clean =~ $m
            or error __x"Invalid value '{value}' for required pattern of {col.name}",
                 value => $clean, col => $self;
    }

    $clean;
}

sub _as_string()
{   my $self = shift;
    my @lines; 
    push @lines, 'is textbox' if $self->is_textbox;
    push @lines, 'match: '. $self->force_regex if $self->force_regex;
    @lines ? (join ', ', @lines) : '';
}

sub string_storage { 1 }

sub resultset_for_values
{   my $self = shift;
    $::db->search(String => { layout_id => $self->id }, { group_by => 'me.value' });
}

sub import_value
{   my ($self, $value) = @_;

    $::db->create(String => {
        record_id    => $value->{record_id},
        layout_id    => $self->id,
        child_unique => $value->{child_unique},
        value        => $value->{value},
        value_index  => $value->{value_index},
    });
}

sub field_values($;$%)
{   my ($self, $datum) = @_;
    my $values = $datum->values;

    # No values, but still need to write null value
    map +{ value => $_, 
           value_index => defined $_ ? (lc substr $_, 0, 128) : '',
         }, @$values ? @$values : (undef);
}

1;

