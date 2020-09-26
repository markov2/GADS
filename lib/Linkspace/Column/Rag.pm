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

#----------- Helper tables
# The Rag table configures the column type.  The Ragval table contains
# the datums.
#
### 2020-09-03: columns in GADS::Schema::Result::Rag
# id         amber      code       green      layout_id  red
#
### 2020-09-03: columns in GADS::Schema::Result::Ragval
# id         value      layout_id  record_id

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

INIT { __PACKAGE__->register_type }

sub value_table   { 'Ragval' }
sub has_fixedvals { 1 }
sub form_extras   { [ qw/code_rag no_alerts_rag no_cache_update_rag/ ], [] }

### for Rag presentation only

sub _filter_values { @filter_values }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Rag    => { layout_id => $col_id });
    $::db->delete(Ragval => { layout_id => $col_id });
}

###
### Instance
###

has _rag => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $::db->get_record(Rag => { layout_id => $_[0]->id }) },
);
sub amber { panic 'Legacy' }
sub green { panic 'Legacy' }
sub code  { $_[0]->_rag->code }

sub _column_extra_update($)
{   my ($self, $update) = @_;
    my $code = delete $update->{code} || delete $update->{code_rag};
    defined $code or return;

    my %data = (code => $code);
    my $reload_id;
    if(my $old = $self->_rag)
    {   $::db->update(Rag => $old->id, \%data);
        $reload_id = $old->id;
    }
    else
    {   $data->{layout_id} = $self->id
        my $result = $::db->create(Rag => \%data);
        $reload_id = $result->id;
    }
    $self->_rag($::db->get_record(Rag => $reload_id));
}

sub id_as_string
{   my ($self, $id) = @_;
    $id or return '';
    $rag_id2string{$id} or panic "Unknown RAG ID $id";
}

1;
