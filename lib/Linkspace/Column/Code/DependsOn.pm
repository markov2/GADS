## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Code::DependsOn;

use Log::Report   'linkspace';
use Linkspace::Util qw/index_by_id to_id list_diff/;

use Moo;

### 2020-08-26: columns in GADS::Schema::Result::LayoutDepend
# id         depends_on layout_id

has column      => (is => 'ro', required => 1);

sub _depends_on()
{   my $self = shift;
my $x =
    $self->{LCCD_deps} ||=
        [ $::db->search(LayoutDepend => {layout_id => $self->column->id})->get_column('depends_on')->all ];
use Data::Dumper;
warn Dumper $x;
$x;
}

sub column_ids { [ map $_->depends_on_id, values %{$_[0]->_depends_on} ] }

sub columns    { [ $_[0]->columns($_[0]->column_ids) ] }

sub count      { scalar keys %{$_[0]->_depends_on} }

sub set_dependencies($)
{   my ($self, $deps) = @_;
    my @deps   = map to_id($_), grep ! $_->is_internal, @$deps;  #XXX why only the user-defined?
    @deps or return;

    my $col_id = $self->column->id;

    my ($add, $del) = list_diff $self->_depends_on, \@deps;
    @$add || @$del or return;

    $::db->delete(LayoutDepend => { layout_id => $col_id, depends_on => $_ }) for @$del;
    $::db->create(LayoutDepend => { layout_id => $col_id, depends_on => $_ }) for @$add;
    delete $self->{LCCD_deps};
}

1;
