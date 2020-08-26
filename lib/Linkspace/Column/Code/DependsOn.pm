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

package Linkspace::Column::Code::DependsOn;

use Log::Report   'linkspace';
use Linkspace::Util qw/index_by_id to_id/;

use Moo;
extends 'Linkspace::DB::Table';

use namespace::clean;

sub db_table() { 'LayoutDepend' }

sub db_field_rename { +{
    depends_on  => 'depends_on_id',
} }

__PACKAGE__->db_accessors;

### 2020-08-26: columns in GADS::Schema::Result::LayoutDepend
# id         depends_on layout_id

has column => (
    is       => 'ro',
    required => 1,
);

has _depends_on => (
    is      => 'lazy',
    builder => sub { index_by_id $_[0]->search_objects({column => $_[0]->column}) },
);

sub column_ids { [ map $_->depends_on_id, values %{$_[0]->_depends_on} ] }

sub columns    { [ $_[0]->columns($_[0]->column_ids) ] }

sub count      { scalar keys %{$_[0]->_depends_on} }

sub set_dependencies($)
{   my ($self, $deps) = @_;
    defined $deps or return;

    my ($add, $del) = $self->set_record_list(
       { column => $column },
       [ map +{ depends_on => $_, column => $self }, @$deps ],
       sub { $_[0]->{depends_on} == $_[1]->depends_on_id },
    );

    my $index = $self->_depends_on;
    delete $index->{$_} for @$del;
    $index->{$_} = __PACKAGE__->from_id($_) for @$add;
}

1;
