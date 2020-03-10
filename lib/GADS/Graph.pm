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

package Linkspace::Graph;

use JSON qw(decode_json encode_json);
use Log::Report 'linkspace';
use Linkspace::Util qw(is_valid_id);

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
use namespace::clean;

my @graph_types      = qw/bar line donut scatter pie/;
my @trend_options    = qw/aggregate individual/;
my @stack_options    = qw/count sum/;
my @grouping_options = qw/day month year/;

#----------------
=head2 METHODS: Constructors
=cut

sub from_record($%)
{   my ($class, $record, %args) = @_;
    bless $record, $class;
}

sub from_id($%)
{   my ($class, $id) = (shift, shift);
    my $record = $::db->get_record(Graph => $id);
	$class->from_record($record, @_);
}

#----------------
=head2 METHODS: Generic accessors
=cut

has sheet => (
    is      => 'lazy',
    weakref => 1,
    builder => sub {  $::session->site->sheet($_[0]->instance_id) },
);

#----------------
=head2 METHODS: Axis
=cut

### rename table columns
sub x_axis_id      { $_[0]->SUPER::x_axis }
sub x_axis_link_id { $_[0]->SUPER::x_axis_link }
sub group_by_id    { $_[0]->SUPER::group_by }

has x_axis => (
    lazy    => 1,
    builder => sub { $_[0]->sheet->column($_[0]->x_axis_id) }
);

has x_axis_link => (
    lazy    => 1,
    builder => sub { $_[0]->sheet->column($_[0]->x_axis_link_id) }
);

has group_by => (
    lazy    => 1,
    builder => sub { $_[0]->sheet->column($_[0]->group_by_id) }
);

sub x_axis_full
{   my $self = shift;
    my $link_id = $self->x_axis_link_id;
    ($link_id ? $link_id.'_' : '') . $self->x_axis_id;
}

# X-axis is undef for graph showing all columns in view
sub x_axis_name { my $x = $_[0]->x_axis; $x ? $x->name : '' }

sub from_formatted
{   my $self = shift;
    $::session->user->dt2local($self->from);
}

sub to_formatted
{   my $self = shift;
    $::session->user->dt2local($self->to);
}

# Legend is shown for secondary groupings. No point otherwise.
sub showlegend
{   my $self = shift
       $graph->group_by_id
    || $graph->type eq 'pie' || $graph->type eq 'donut'
    || $graph->trend;
);

# Whether a user has the graph selected. Used by GADS::Graphs
has selected => (
    is     => 'rw',
    isa    => Bool,
    coerce => sub { $_[0] ? 1 : 0 },
);

sub writable
{   my $self = shift;
        $sheet->user_can("layout")
    || ($self->group_id && $sheet->user_can("view_group"))
    || ($self->user_id && $::session->user->id == $self->user_id);
}

sub as_json
{   my $self = shift;
    encode_json {
        type         => $self->type,
        x_axis_name  => $self->x_axis_name,
        y_axis_label => $self->y_axis_label,
        stackseries  => \$self->stackseries,
        showlegend   => \$self->showlegend,
        id           => $self->id,
    };
}

# Rarely called, so do not build hashes
sub _in($@) { my $which = shift; first { $which eq $_ } @_ }

sub validate($$$)
{   my ($class, $graph_id, $sheet, $params) = @_;
    my $old;

    if($graph_id)
    {   $old = $sheet->graphs->graph($graph_id);
        $old->writable
            or error __"You do not have permission to write to this graph";
    }

    my $type  = $params->{type};
    _in($type, @graph_types)
        or error __x"Invalid graph type {type}", type => $type;

    my $title = $params->{title}
        or error __"Please enter a title";

    my $y_axis_id = $params->{y_axis};
    is_valid_id $y_axis_id
        or error __x"Invalid Y-axis {y_axis_id}", y_axis_id => $y_axis_id;

    my $y_axis = $sheet->column($y_axis_id)
        or error __x"Unknown Y-axis column {y_axis_id}", y_axis_id => $y_axis_id;

    my $y_axis_stack = $params->{y_axis_stack}
        or error __"A valid value is required for Y-axis stacking";

    _in($y_axis_stack, @stack_options)
        or error __x"{yas} is not a invalid value for Y-axis", yas => $y_axis_stack;

    if($y_axis_stack eq 'sum')
    {   $y_axis or error __"Please select a Y-axis";
        $y_axis->numeric
            or error __"A field returning a numberic value must be used for the Y-axis when calculating the sum of values ";
    }

    my ($x_axis_link_id, $x_axis_id) = $param->{set_x_axis} =~
        /^(([0-9]+)_([0-9]+))$/ ? ($2, $3) : (undef, $1);

    my $x_axis_id = $params->{x_axis};
    is_valid_id $x_axis_id
        or error __x"Invalid X-axis value {x_axis_id}", x_axis_id => $x_axis_id;

    my $x_axis = $sheet->column($x_axis_id)
        or error __x"Unknown X-axis column {x_axis_id}", x_axis_id => $x_axis_id;

    my $trend = $params->{trend}
    !$trend || _in($trend, @trend_options)
        or error __x"Invalid trend value: {trend}", trend => $trend;

    my $x_axis_range = $params->{x_axis_range};
    error __"An x-axis range must be selected when plotting historical trends"
        if $trend && !$x_axis_range;

    my $xgroup = $params->{x_axis_grouping};
    ! defined $xgroup || _in($xgroup, @grouping_options)
        or error __x"{xas} is an invalid value for X-axis grouping", xas => $xgroup;

    my $group_by_id = $params->{group_by};
    ! defined $group_by_id || $sheet->column($group_by_id)
        or error __x"Invalid group by value {group_by}", group_by => $group_by_id;

    $group_by_id && $trend
        and error __"Historical trends cannot be used with y-axis grouping (Group by)";

    my $mg_id;
    if(my $mgi = $params->{metric_group_id})
    {   $mg_id = is_valid_id $mgi
            or error __x"Invalid metric group ID format {id}", id => $mgi;

        $sheet->graphs->metric_groups($mg_id)
            or error __x"Unknown metric group ID {id}", id => $mg_id;
    }

    my $is_shared = $params->{is_shared} || 0;
    my $group_id  = is_valid_id $params->{group_id};

       ! $is_shared
    || ($sheet->user_can("layout") || ($group_id && $sheet->user_can('view_group')))
       or error __"You do not have permission to create shared graphs"

    my $user_id = $params->{user_id} || $::session->user->id;

    +{  type           => $type,
        as_percent     => $params->{as_percent}  || 0,
        description    => $params->{description},
        from           => $params->{from}        || undef,  # reset blank fields
        group_by       => $group_by_id,
        group_id       => $group_id,
        is_shared      => $is_shared,
        metric_group_id=> $mg_id,
        stackseries    => $params->{stackseries} || 0,
        title          => $title,
        to             => $params->{to}          || undef,
        trend          => $trend,
        user_id        => $is_shared ? undef : $user_id,
        x_axis         => $x_axis_id,
        x_axis_grouping=> $xgroup,
        x_axis_link    => $x_axis_link_id,
        x_axis_range   => $x_axis_range,
        y_axis         => $y_axis_id,
        y_axis_label   => $params->{y_axis_label},
        y_axis_stack   => $y_axis_stack,
     };
}

sub show_changes($%)
{   my ($self, $values, %options) = @_;

    no warnings "uninitialized";
    notice __x"Updating title from {old} to {new} for graph {name}",
        old => $self->title, new => $values->{title}, name => $self->title
            if $self->title ne $values->{title};

    my $name = $values->{title} || $self->title;

    notice __x"Updating description from {old} to {new} for graph {name}",
        old => $self->description, new => $values->{description}, name => $name
            if $self->description ne $values->{description};

    notice __x"Updating y_axis from {old} to {new} for graph {name}",
        old => $self->y_axis, new => $values->{y_axis}, name => $name
            if $self->y_axis != $values->{y_axis};

    notice __x"Updating y_axis_stack from {old} to {new} for graph {name}",
        old => $self->y_axis_stack, new => $values->{y_axis_stack}, name => $name
            if $self->y_axis_stack ne $values->{y_axis_stack};

    notice __x"Updating y_axis_label from {old} to {new} for graph {name}",
        old => $self->y_axis_label, new => $values->{y_axis_label}, name => $name
            if $self->y_axis_label ne $values->{y_axis_label};

    notice __x"Updating x_axis from {old} to {new} for graph {name}",
        old => $self->x_axis, new => $values->{x_axis}, name => $name
            if $self->x_axis != $values->{x_axis};

    notice __x"Updating x_axis_link from {old} to {new} for graph {name}",
        old => $self->x_axis_link, new => $values->{x_axis_link}, name => $name
            if $self->x_axis_link != $values->{x_axis_link};

    notice __x"Updating x_axis_grouping from {old} to {new} for graph {name}",
        old => $self->x_axis_grouping, new => $values->{x_axis_grouping}, name => $name
            if $self->x_axis_grouping ne $values->{x_axis_grouping};

    notice __x"Updating group_by from {old} to {new} for graph {name}",
        old => $self->group_by, new => $values->{group_by}, name => $name
            if $self->group_by != $values->{group_by};

    notice __x"Updating stackseries from {old} to {new} for graph {name}",
        old => $self->stackseries, new => $values->{stackseries}, name => $name
            if $self->stackseries != $values->{stackseries};

    notice __x"Updating trend from {old} to {new} for graph {name}",
        old => $self->trend, new => $values->{trend}, name => $name
            if $self->trend != $values->{trend};

    notice __x"Updating from from {old} to {new} for graph {name}",
        old => $self->from, new => $values->{from}, name => $name
            if ($self->from || '') ne ($values->{from} || '');

    notice __x"Updating to from {old} to {new} for graph {name}",
        old => $self->to, new => $values->{to}, name => $name
            if ($self->to || '') ne ($values->{to} || '');

    notice __x"Updating x_axis_range from {old} to {new} for graph {name}",
        old => $self->x_axis_range, new => $values->{x_axis_range}, name => $name
            if ($self->x_axis_range || '') ne ($values->{x_axis_range} || '');

    notice __x"Updating is_shared from {old} to {new} for graph {name}",
        old => $self->is_shared, new => $values->{is_shared}, name => $name
            if $self->is_shared != $values->{is_shared};

    notice __x"Updating user_id from {old} to {new} for graph {name}",
        old => $self->user_id, new => $values->{user_id}, name => $name
            if ($self->user_id || 0) != ($values->{user_id} || 0);

    notice __x"Updating group_id from {old} to {new} for graph {name}",
        old => $self->group_id, new => $values->{group_id}, name => $name
            if ($self->group_id || 0) != ($values->{group_id} || 0);

    notice __x"Updating as_percent from {old} to {new} for graph {name}",
        old => $self->as_percent, new => $values->{as_percent}, name => $name
            if $self->as_percent != $values->{as_percent};

    notice __x"Updating type from {old} to {new} for graph {name}",
        old => $self->type, new => $values->{type}, name => $name
            if $self->type ne $values->{type};

    notice __x"Updating metric_group_id from {old} to {new} for graph {name}",
        old => $self->metric_group_id, new => $values->{metric_group_id}, name => $name
            if $self->metric_group_id != $values->{metric_group_id};
}

sub export_hash
{   my $self = shift;
    +{
        title           => $self->title,
        description     => $self->description,
        y_axis          => $self->y_axis,
        y_axis_stack    => $self->y_axis_stack,
        y_axis_label    => $self->y_axis_label,
        x_axis          => $self->x_axis,
        x_axis_link     => $self->x_axis_link,
        x_axis_grouping => $self->x_axis_grouping,
        group_by        => $self->group_by,
        stackseries     => $self->stackseries,
        trend           => $self->trend,
        from            => $self->from,
        to              => $self->to,
        x_axis_range    => $self->x_axis_range,
        is_shared       => $self->is_shared,
        user_id         => $self->user_id,
        group_id        => $self->group_id,
        as_percent      => $self->as_percent,
        type            => $self->type,
        metric_group_id => $self->metric_group_id,
    };
}

1;
