## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Code::DependsOn;

use Log::Report   'linkspace';
use Linkspace::Util qw/index_by_id to_id/;

use Moo;
extends 'Linkspace::DB::Table';

use namespace::clean;

sub db_table() { 'LayoutDepend' }

sub db_field_rename { +{
    depends_on  => 'depends_on_id',
} };

__PACKAGE__->db_accessors;

### 2020-08-26: columns in GADS::Schema::Result::LayoutDepend
# id         depends_on layout_id

has column => (is => 'ro', required => 1);

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

    my @deps = grep ! $_->internal, @$deps;  #XXX why only the user-defined?

    my ($add, $del) = $self->set_record_list(
       { column => $self->column },
       [ map +{ depends_on => $_, column => $self }, @deps ],
       sub { $_[0]->{depends_on} == $_[1]->depends_on_id },
    );

    my $index = $self->_depends_on;
    delete $index->{$_} for @$del;
    $index->{$_} = __PACKAGE__->from_id($_) for @$add;
}

1;
