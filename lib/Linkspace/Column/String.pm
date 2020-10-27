## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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
sub string_storage      { 1 }

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

1;

