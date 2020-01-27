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

package Linkspace::Column::Rag;

use Moo;
extends 'Linkspace::Column::Code';
with 'Linkspace::Role::Presentation::Column::Rag';

use Log::Report 'linkspace';

my @filter_values = (
    [ b_red    => 'Red'    ],
    [ c_amber  => 'Amber'  ],
    [ c_yellow => 'Yellow' ],
    [ a_grey   => 'Grey'   ],
    [ d_green  => 'Green'  ],
    [ e_purple => 'Purple' ],
);

my %rag_id2string = map @$_, @filter_values;

###
### META
###

__PACKAGE__->register_type;

sub table     { 'Ragval' }
sub fixedvals { 1 }

### for Rag presentation only

sub _filter_values { @filter_values }

###
### Class
###

sub remove($)
{   my $col_id = $_[1]->id;
    $::db->delete(Rag    => { layout_id => $col_id });
    $::db->delete(Ragval => { layout_id => $col_id });
}

###
### Instance
###

sub _build__rset_code
{   my $self = shift;
    $self->_rset or return;
    my ($code) = $self->_rset->rags;

    $code || $::db->resultset('Rag')->new({});
}

sub id_as_string
{   my ($self, $id) = @_;
    $id or return '';
    $rag_id2string{$id} or panic("Unknown RAG ID $id");
}

# Returns whether an update is needed
sub write_code
{   my ($self, $layout_id) = @_;
    my $rset = $self->_rset_code;
    my $need_update = !$rset->in_storage
        || $self->_rset_code->code ne $self->code;
    $rset->layout_id($layout_id);
    $rset->code($self->code);
    $rset->insert_or_update;
    $need_update;
}

before import_hash => sub {
    my ($self, $values, %options) = @_;
    my $report = $options{report_only} && $self->id;
    notice __x"Update: RAG code has changed for {name}", name => $self->name
        if $report && $self->code ne $values->{code};
    $self->code($values->{code});
};

sub export_hash
{   my $self = shift;
    my $hash = $self->SUPER::export_hash;
    $hash->{code} = $self->code;
    $hash;
}

1;
