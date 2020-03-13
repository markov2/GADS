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

use Log::Report 'linkspace';
use JSON            qw(decode_json encode_json);
use Linkspace::Util qw(is_valid_id);
use List::Util      qw(any);

use Moo;
use namespace::clean;
extends 'Linkspace::DB::Table';

### 2020-03-13: columns in GADS::Schema::Result::Graph
# id              description     stackseries     x_axis_range
# instance_id     from            to              y_axis
# title           group_by        trend           y_axis_label
# type            group_id        x_axis          y_axis_stack
# user_id         is_shared       x_axis_grouping
# as_percent      metric_group    x_axis_link

sub db_table { 'Graph' }

sub db_field_rename
{  +{ group_by    => 'group_by_id',
      x_axis      => 'x_axis_id',
      x_axis_link => 'x_axis_link_id',
      y_axis      => 'y_axis_id',
    };
}

my @graph_types      = qw/bar line donut scatter pie/;
my @trend_options    = qw/aggregate individual/;
my @stack_options    = qw/count sum/;
my @grouping_options = qw/day month year/;

#----------------

=head1 NAME
Linkspace::Graph - graph definition

=head1 DESCRIPTION
Per sheet, a set of graphs can be defined.  They are managed by the
L<Linkspace::Sheet::Graphs> helper object of the sheet.  Graphs get
their data from columns and metrics.

=head1 METHODS: Axis
=cut

has x_axis      => (lazy => 1, builder => sub { $_[0]->column($_[0]->x_axis_id)   });
has x_axis_link => (lazy => 1, builder => sub { $_[0]->column($_[0]->x_axis_link_id) });
has y_axis      => (lazy => 1, builder => sub { $_[0]->column($_[0]->y_axis_id)   });
has group_by    => (lazy => 1, builder => sub { $_[0]->column($_[0]->group_by_id) });

sub x_axis_full
{   my $self = shift;
    my $link_id = $self->x_axis_link_id;
    ($link_id ? $link_id.'_' : '') . $self->x_axis_id;
}

sub uses_column($)
{   my ($self, $which) = @_;
    my $col_id = blessed $which ? $which->id : $which;
    $_->x_axis_id==$col_id || $_->y_axis_id==$col_id || $_->group_by_id==$col_id;
}

#----------------
=head1 METHODS: Display
=cut

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

sub showlegend
{   my $self = shift;
       $self->group_by_id
    || $self->type eq 'pie' || $self->type eq 'donut'
    || $self->trend;
}

sub writable
{   my $self = shift;

        $self->sheet->user_can('layout')
    || ($self->group_id && $self->sheet->user_can('view_group'))
    || ($self->user_id  && $::session->user->id == $self->user_id);
}

sub legend_as_json
{   my $self = shift;

    # Legend is shown for secondary groupings. No point otherwise.
    encode_json +{
        type         => $self->type,
        x_axis_name  => $self->x_axis_name,
        y_axis_label => $self->y_axis_label,
        stackseries  => \$self->stackseries,
        showlegend   => \$self->showlegend,
        id           => $self->id,
    };
}

sub validate($$$)
{   my ($class, $graph_id, $sheet, $params) = @_;
    my $old;

    if($graph_id)
    {   $old = $sheet->graphs->graph($graph_id);
        $old->writable
            or error __"You do not have permission to write to this graph";
    }

    my $type  = $params->{type};
    any { $type eq $_ } @graph_types
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

    any { $y_axis_stack eq $_ } @stack_options
        or error __x"{yas} is not a invalid value for Y-axis", yas => $y_axis_stack;

    if($y_axis_stack eq 'sum')
    {   $y_axis or error __"Please select a Y-axis";
        $y_axis->numeric
            or error __"A field returning a numberic value must be used for the Y-axis when calculating the sum of values ";
    }

    my ($x_axis_link_id, $x_axis_id) = $params->{set_x_axis} =~
        /^\s*(([0-9]+)_([0-9]+))\s*$/ ? ($2, $3) : (undef, $1);

    is_valid_id $x_axis_id
        or error __x"Invalid X-axis value {x_axis_id}", x_axis_id => $x_axis_id;

    my $x_axis = $sheet->column($x_axis_id)
        or error __x"Unknown X-axis column {x_axis_id}", x_axis_id => $x_axis_id;

    my $trend = $params->{trend};
    !$trend || any { $trend eq $_ } @trend_options
        or error __x"Invalid trend value: {trend}", trend => $trend;

    my $x_axis_range = $params->{x_axis_range};
    error __"An x-axis range must be selected when plotting historical trends"
        if $trend && !$x_axis_range;

    my $xgroup = $params->{x_axis_grouping};
    ! defined $xgroup || any { $xgroup eq $_ } @grouping_options
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
       or error __"You do not have permission to create shared graphs";

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

1;
