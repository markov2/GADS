## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::Metric;

use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

# Only needed when manipulating the object
has schema => (
    is => 'ro',
);

has id => (
    is  => 'rwp',
);

has metric_group_id => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_rset->get_column('metric_group') },
);

has x_axis_value => (
    is      => 'rw',
    isa     => Str,
    lazy    => 1,
    builder => sub { $_[0]->_rset->x_axis_value },
);

# No type so as to accept anything from input form
has target => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_rset->target },
);

has y_axis_grouping_value => (
    is      => 'rw',
    isa     => Str,
    lazy    => 1,
    builder => sub { $_[0]->_rset->y_axis_grouping_value },
);

has _rset => (
    is => 'lazy',
);

sub _build__rset
{   my $self = shift;
    my $rset;
    if ($self->id)
    {
        $self->id =~ /^[0-9]+$/
            or error __x"Invalid id {id}", id => $self->id;
        $rset = $self->schema->resultset('Metric')->find($self->id)
            or error __x"Metric ID {id} not found", id => $self->id;
    }
    else {
        $self->metric_group_id =~ /^[0-9]+$/
            or error __x"Invalid metric group ID {id}", id => $self->metric_group_id;
        $rset = $self->schema->resultset('Metric')->create({
            metric_group => $self->metric_group_id,
        });
    }
    $rset;
}

sub write
{   my $self = shift;
    $self->target =~ /^[0-9]+$/
        or error "Please enter an integer value for the target";
    $self->_rset->update({
        metric_group          => $self->metric_group_id,
        x_axis_value          => $self->x_axis_value,
        y_axis_grouping_value => $self->y_axis_grouping_value,
        target                => $self->target,
    });
}

1;


