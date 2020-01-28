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

package GADS::Graphs;

use Log::Report      'linkspace';
use Scalar::Util     qw/blessed/;
use Linkspace::util  qw/index_by_id/;
use Linkspace::Graph;

my @graph_types =    qw/bar line donut scatter pie/;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use namespace::clean;

has sheet => (
    is       => 'ro',
    required => 1,
    weakref  => 1,
);

has all_graphs => (
    is      => 'lazy',
);

sub _build_all_graphs()
{   my $self     = shift;
    my $user_id  = $::session->user;
    my $sheet_id = $self->sheet->id;

    # First create a hash of all the graphs the user has selected
    my %user_selected = index_by_id
        $::db->search(Graph => {
            'user_graphs.user_id' => $user_id,
            instance_id           => $sheet_id,
        },{
            join => 'user_graphs',
        })->all;

    # Now get all graphs, and use the previous hash to see
    # if the user has this graph selected
    my @all_graph_ids = $::db->search(Graph => {
    {
        instance_id => $sheet_id,
        -or         => [
            {
                'me.is_shared' => 1,
                'me.group_id'  => undef,
            },
            {
                'me.is_shared' => 1,
                'user_groups.user_id' => $user_id,
            },
            {
                'me.user_id'   => $user_id,
            },
        ],
    },{
        join       => { group => 'user_groups' },
        collapse   => 1,
        order_by   => 'me.title',
        result_set => 'HASH',
    })->get_column('id')->all;

    #XXX merging 'selected' in here is bad for caching.
    my @graphs = map $self->graph($_, selected => $user_selected{$_}),
        @all_graph_ids;

    \@graphs;
}

has all_shared => (
    is      => 'lazy',
    builder => sub { [ grep $_->is_shared, @{$self->all_graphs} ] },
);

has all_personal => (
    is      => 'lazy',
    builder => sub { [ grep !$_->is_shared, @{$self->all_groups} ] },
);

has all_all_users => (
    is => 'lazy',
);

#XXX should maybe be merged in all_graphs when user->is_admin
sub _build_all_all_users
{   my $self = shift;

    my @all_graph_ids = $::db->search(Graph => { instance_id => $self->sheet->id })
        ->get_column('id')->all;

    [ map $self->graph($_), @all_graph_ids ];
}

sub purge
{   my $self = shift;
    $_->graph_delete for @{$self->all_graphs};
}

sub types { @graph_types }

sub graphs_using_column($)
{   my ($self, $column) = @_;
    $column or return;

    my $col_id    = $column->id;
    my @graph_ids = $::db->search(Graph => [
        { x_axis   => $col_id },
        { y_axis   => $col_id },
        { group_by => $col_id },
    ])->get_column('id')->all;

   [ map $self->graph($_), @graph_ids ];
}

1;


