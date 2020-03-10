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

package Linkspace::Sheet::Graphs;

use Log::Report      'linkspace';
use Scalar::Util     qw/blessed/;

use Linkspace::Util  qw/index_by_id/;
use Linkspace::Graph ();

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use namespace::clean;

#--------------------
=head1 METHODS: Generic Attributes
=cut

has sheet => (
    is       => 'ro',
    required => 1,
    weakref  => 1,
);

sub purge
{   my $self = shift;
    $self->graph_delete($_) for @{$self->all_graphs};
}

#--------------------
=head1 METHODS: Manage Graphs
=cut

#XXX all graphs for this user
has user_graphs => (
    is      => 'lazy',
);

sub _build_user_graphs()
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

sub all_shared   { [ grep  $_->is_shared, @{$_[0]->user_graphs} ] }
sub all_personal { [ grep !$_->is_shared, @{$_[0]->user_graphs} ] }

has all_all_users => (
    is => 'lazy',
);

#XXX should maybe be merged in user_graphs when user->is_admin
sub _build_all_all_users
{   my $self = shift;

    my @all_graph_ids = $::db->search(Graph => { instance_id => $self->sheet->id })
        ->get_column('id')->all;

    [ map $self->graph($_), @all_graph_ids ];
}

sub graphs_using_column($)
{   my ($self, $which) = @_;
    my $col_id = ! defined $which ? return : blessed $which ? $which->id : $which;

    [ grep $_->x_axis_id==$col_id || $_->y_axis_id==$col_id || $_->group_by_id==$col_id,
        @{$self->user_graphs} ];
}

sub graph_delete($)
{   my ($self, $which) = @_;
    my $graph_id = ! defined $which ? return : blessed $which ? $which->id : $which;

    my $graph = $self->graph($graph_id) or return;
    $graph->writable
        or error __"You do not have permission to delete this graph";

    $::db->update(Widget => { graph_id => $graph_id }, { graph_id => undef });
    $::db->delete(UserGraph => { graph_id => $graph_id });
    $::db->delete(Graph => $graph_id);
}

sub graph($)
{   my ($self, $graph_id) = @_;
    $graph_id or return;

    my $record = $self->_graphs_index->{$graph_id};
    $record->isa('Linkspace::Graph')
        or Linkspace::Graph->from_record($record);
}

#--------------------
=head1 METHODS: Manage Metric Groups

=head2 \@mg = $graphs->metric_groups;
Returns the metric groups for this sheet.
=cut

sub metric_groups()
{   my ($self) = @_;

GADS::MetricGroups->new(
            instance_id => session('persistent')->{instance_id},
        )->all;

}

sub all_metric_groups()
{
}

1;


