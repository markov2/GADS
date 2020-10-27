## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

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

=head2 my @graphs = $graphs->all_graphs;
Returns all graphs for this sheet.
=cut

has _graphs_index => (
	is      => 'lazy',
    builder => sub {
       index_by_id $::db->search(Graph => { instance_id => $_[0]->sheet->id })->all;
);

sub all_graphs()
{   my $self = shift;
    [ map $self->graph($_), values %{$self->_graphs_index} ];
}

=head2 my $graphs = $graphs->user_graphs(%options);
Returns the graphs where the session user has access to, ordered by title.
With the C<shared> option, you can restrict to getting personal or shared
graphs.
=cut

sub user_graphs(%)
{   my ($self, %args) = @_;
    my $user_id = ($args{user} || $::session->user)->id;

    my @mine = grep
     +( $_->is_shared
      ? ( ! $_->group_id || $user->is_in_group($_->group_id) )
      : $_->user_id==$user_id
      ), values %{$self->_graph_index};

    @mine = grep !!$args{shared} == !!$_->is_shared, @mine
        if exists $args{shared};

    [ map $self->graph($_->id), sort { $a->title cmp $b->title } @mine ];
}

=head2 $graphs->graph_delete($which);
Remove a graph, which is specified as object or by id.  All referenced to the
graph will be removed as well.
=cut

sub graph_delete($)
{   my ($self, $which) = @_;
    my $graph_id = ! defined $which ? return : blessed $which ? $which->id : $which;

    my $graph = $self->graph($graph_id) or return;
    $graph->writable
        or error __"You do not have permission to delete this graph";

    $::db->update(Widget => { graph_id => $graph_id }, { graph_id => undef });
    $::db->delete(UserGraph => { graph_id => $graph_id });
    $::db->delete(Graph => $graph_id);
    $self;
}

=head2 my $graph = $graphs->graph($which);
Returns an object based on L<Linkspace::Graph>.  You may specify a graph by id,
record, or object.
=cut

sub graph($)
{   my ($self, $which) = @_;
    $which or return;

    my $record = blessed $which ? $which : $self->_graphs_index->{$which};
    return $record if $record->isa('Linkspace::Graph');

    $self->_graphs_index->{$graph} = Linkspace::Graph->from_record($record);
}

#--------------------
=head1 METHODS: Manage Metric Groups

=head2 \@mg = $graphs->metric_groups;
Returns the metric groups for this sheet.
=cut

sub metric_groups()
{   my ($self) = @_;

GADS::MetricGroups->new( instance_id => $sheet->id)->all;

}

sub all_metric_groups()
{
}

1;


