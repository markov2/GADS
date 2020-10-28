## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::MetricGroups;

use GADS::MetricGroup;
use Log::Report 'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw(:all);

has schema => (
    is       => 'ro',
    required => 1,
);

has instance_id => (
    is       => 'ro',
    isa      => Int,
    required => 1,
);

has all => (
    is      => 'lazy',
);

sub _build_all
{   my $self = shift;

    my @metrics;

    my @all = $self->schema->resultset('MetricGroup')->search(
    {
        instance_id => $self->instance_id,
    },{
        order_by => 'me.name',
    });
    foreach my $metric (@all)
    {
        push @metrics, GADS::MetricGroup->new({
            id          => $metric->id,
            name        => $metric->name,
            schema      => $self->schema,
            instance_id => $self->instance_id,
        });
    }

    \@metrics;
}

sub purge
{   my $self = shift;
    foreach my $mg (@{$self->all})
    {
        $mg->delete;
    }
}

1;


