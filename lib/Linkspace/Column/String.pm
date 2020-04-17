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
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column';

###
### META
###

__PACKAGE__->register_type;

sub can_multivalue      { 1 }
sub form_extras         { [ qw/textbox force_regex/ ], [] }
sub has_multivalue_plus { 1 }

###
### Class
###

sub remove($)
{   my $col_id = $_[1]->id;
    $::db->delete(String => { layout_id => $col_id });
}

###
### Instance
###

sub string_storage { 1 }

has textbox => (
    is      => 'rw',
    isa     => Bool,
    lazy    => 1,
    default => 0,
    coerce  => sub { $_[0] ? 1 : 0 },
);

has force_regex => (
    is      => 'rw',
    isa     => Maybe[Str],
    lazy    => 1,
);

after build_values => sub {
    my ($self, $original) = @_;
    $self->textbox(1) if $original->{textbox};

    if(my $force_regex = $original->{force_regex})
    {   $self->force_regex($force_regex);
    }
};

sub write_special
{   my ($self, %options) = @_;

    my $rset = $options{rset};

    $rset->update({
        textbox     => $self->textbox,
        force_regex => $self->force_regex,
    });

    return ();
}

sub resultset_for_values
{   my $self = shift;
    $::db->search(String => { layout_id => $self->id }, { group_by => 'me.value' });
}

before import_hash => sub {
    my ($self, $values, %options) = @_;
    my $report = $options{report_only} && $self->id;
    notice __x"Update: textbox from {old} to {new}", old => $self->textbox, new => $values->{textbox}
        if $report && $self->textbox != $values->{textbox};

    $self->textbox($values->{textbox});
    notice __x"Update: force_regex from {old} to {new}", old => $self->force_regex, new => $values->{force_regex}
        if $report && ($self->force_regex || '') ne ($values->{force_regex} || '');
    $self->force_regex($values->{force_regex});
};

sub export_hash
{   my $self = shift;
    $self->SUPER::export_hash(@_,
        textbox => $self->textbox,
        force_regex => $self->force_regex,
    );
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
           value_index => defined ? (lc substr $_, 0, 128) : '',
         }, @$values ? @$values : (undef);
}

1;

