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

package Linkspace::Graph::Data;

use HTML::Entities;
use JSON qw(decode_json encode_json);
use List::Util qw(sum);
use Math::Round qw(round);
use Text::CSV::Encoded;
use Scalar::Util qw(looks_like_number);

use Moo;

extends 'Linkspace::Graph';

has records => (
    is       => 'rw',
    required => 1,
);

has view => (
    is => 'ro',
);

has xlabels => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_data->{xlabels} },
);

has labels => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_data->{labels} },
);

sub labels_encoded()
{   my $labels = shift->labels;
    [ map +{ %$_, label => encode_entities($_->{label}) }, @$labels ];
}

has points => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_data->{points} },
);

has options => (
    is      => 'ro',
    lazy    => 1,
    builder => sub { $_[0]->_data->{options} },
);

# Function to fill out the series of data that will be plotted on a graph
has _data => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $_[0]->_build_data },
);

# Specific colours to match rag fields
my $red    = 'D9534F';
my $amber  = 'F0AD4E';
my $yellow = 'FCFC4B';
my $green  = '5CB85C';
my $grey   = '8C8C8C';
my $purple = '4B0F44';

my @other_colors = qw/
  007B45 1C75BC 2C4269 34C3E0 4D4C4C 51417B 7A221B 7F3F98 97C9B3 9F6512
  B0B11A BDE0E9 D1D3D4 EE2D72 F0679E F26522 F37970 F9DDB6 FFDD00 FFED7D
/;

has _colors_unused => (
    is      => 'ro',
    default => sub {
        #XXX not yellow?
        +{ map +($_ => 1), @other_colors, $red, $amber, $green, $grey, $purple };
    },
);

has _colors_in_use => (
    is      => 'ro',
    default => sub { +{} },
);

sub get_color
{   my ($self, $value) = @_;

    # Make sure value doesn't exceed the length of the name column,
    # otherwise we won't match when trying to find it.
    my $gc_rs = $::db->resultset('GraphColor');
    my $size = $gc_rs->result_source->column_info('name')->{size};
    $value = substr $value, 0, $size - 1;

    my $in_use = $self->_colors_unused_in_use;
    return "#".$in_use->{$value}
        if exists $in_use->{$value};

    # $@ may be the result of a previous Log::Report::Dispatcher::Try block (as
    # an object) and may evaluate to an empty string. If so, txn_scope_guard
    # warns as such, so undefine to prevent the warning
    undef $@;
    my $guard = $::db->begin_work;

    my $existing = $gc_rs->find($value, { key => 'ux_graph_color_name' });
    my $color;
    if ($existing && $self->_colors_unused->{$existing->color})
    {   $color = $existing->color;
    }
    else
    {   $color = $value eq 'a_grey'   ? $grey
               : $value eq 'b_red'    ? $red
               : $value eq 'c_amber'  ? $amber
               : $value eq 'c_yellow' ? $yellow
               : $value eq 'd_green'  ? $green
               : $value eq 'e_purple' ? $purple
               : (keys %{$self->_colors_unused})[0];

        $gc_rs->update_or_create({ name  => $value, color => $color }, {
            key => 'ux_graph_color_name'
        }) if $color; # May have run out of colours
    }
    $guard->commit;

    if($color)
    {   $in_use->{$value} = $color;
        delete $self->_colors_unused->{$color};
        $color = "#$color";
    }

    $color;
}

sub as_json
{   my $self = shift;
    encode_json {
        points  => $self->points,
        labels  => $self->labels_encoded,
        xlabels => $self->xlabels,
        options => $self->options,
    };
}

has graph => (
    is       => 'ro',
    required => 1,
);

sub x_axis_time_units
{   my $self   = shift;
    my $graph  = $self->graph;
    my $x_axis = $graph->x_axis or return undef;

    # Only try grouping by date for valid date column
    return undef
        if ! $graph->trend
        && $x_axis->return_type ne 'date'
        && $x_axis->return_type ne 'daterange';

    my $x_range = $graph->x_axis_range || '';
    return $graph->x_axis_grouping
        if $x_range eq 'custom'
        || (!$graph->trend && $graph->x_axis_grouping);

    return undef
        if !$graph->from && !$graph->to && !$x_range;

    # Work out suitable intervals: short range: day, medium: month, long: year
    my $months = abs $graph->x_axis_range;

      $months ==  1 ? 'day'
    : $months <= 24 ? 'month'
    :                 'year';
}

sub _build_data
{   my $self = shift;
    my $x_axis = $graph->x_axis;

    # If the x-axis field is one from a curval, make sure we are also
    # retrieving the parent curval field (called the link)
    my $link   = $graph->x_axis_link;

    # Columns is either the x-axis, otherwise all the columns in the view
    my $columns
       = $x_axis     ? [ $x_axis ]
       : $self->view ? $self->view->columns
       :               $sheet->layout->columns_search(user_can_read => 1);

    my @columns = map +{
        id        => $_,
        operator  => 'max',
        parent_id => ($x_axis && $_ == $x_axis->id && $link->id)
    }, @$columns;

    # Whether the x-axis is a daterange data type. If so, we need to treat it
    # specially and span values from single records across dates.
    my $x_is_daterange  = $x_axis && $x_axis->return_type eq 'daterange';

    my $x_time_units = $self->x_axis_time_units;
    my %x_time_step  = $x_time_units ? ($x_time_units.'s' => 1) : ();

    push @columns, +{
        id        => $graph->x_axis_id,
        group     => 1,
        pluck     => $x_time_units,  # Whether to group x-axis dates
        parent_id => $link,
    } if !$x_is_daterange && $x_axis;

    push @columns, {
        id    => $self->group_by_id,
        group => 1,
    } if $self->group_by;

    my ($from, $to) = $self->_calculate_range;

    my $records = $self->records;
    unless($self->trend) # If a trend, the from and to will be set later
    {   $records->from($from);
        $records->to($to);
    }

    my $view = $self->view;
    $records->view($view);

    push @columns, +{
        id       => $self->y_axis_id,
        operator => $self->y_axis_stack,
    } if $self->y_axis;

    $records->columns(\@columns);

    # All the sources of the x values. May only be one column, may be several
    # columns, or may be lots of dates.
    my @x;

    if($x_is_daterange)
    {   $records->dr_interval($x_time_units);
        $records->dr_column($x_axis->id);
        $records->dr_column_parent($link);
        $records->dr_y_axis($self->y_axis);

        $self->records->results # Do now so as to populate dr_from and dr_to

        if ($records->dr_from && $records->dr_to)
        {
            # If this is a daterange x-axis, then use the start date
            # as calculated by GADS::Records, then interpolate
            # until the end date. These same values will have been retrieved
            # in the resultset.
            my $pointer = $records->dr_from->clone;
            while ($pointer->epoch <= $records->dr_to->epoch)
            {   push @x, $pointer->clone;
                $pointer->add(%x_time_step);
            }
        }
    }
    elsif($self->x_axis_range)
    {   # Produce a set of dates spanning the required range
        my $pointer = $from->clone;
        while($pointer <= $to)
        {   push @x, $pointer->clone;
            $pointer->add(%x_time_step);
        }
    }
    else
    {   push @x, @$columns;
    }

    # Now go into each of the retrieved database results, and create a more
    # useful hash with all the series on, which we can use to create the
    # graphs. At this point, we do not know what the x-axis values will be,
    # so we need to wait until we've retrieved them all first (we know the
    # source of the values, but not the value or quantity of them).
    #
    # $results - overall results hash
    # $series_keys - the names of all of the series for the graph. May only be one
    # $datemin and $datemax - for x-axis dates, min and max retrieved

    my @xlabels;
    my ($results, $series_keys, $datemin, $datemax);
    if($self->trend)
    {   foreach my $x (@x)
        {
            # The period to retrieve ($x) will be at the beginning of the
            # period. Move to the end of the period, by adding on one unit
            # (e.g. month) and then moving into the previous day by a second
            my $rewind = $x->clone->add($x_time_step)->subtract(seconds => 1);
            $records->rewind($rewind);

            (my $this_results, my $this_series_keys, $datemin, $datemax) = $self->_records_to_results($records,
                x_daterange => $x_is_daterange,
                x           => [ $x_axis ],
                values_only => 1,
            );
            my $label = $self->_time_label($x);
            push @xlabels, $label;
            $results->{$label} = $this_results;
            $series_keys->{$_} = 1
                for keys %$this_series_keys;
        }
    }
    else
    {   ($results, $series_keys, $datemin, $datemax) = $self->_records_to_results($records,
            x_daterange => $x_is_daterange,
            x           => \@x,
        );
    }

    # Work out the labels for the x-axis. We now know this having processed
    # all the values.
    if($x_time_units && $datemin && $datemax)
    {   @xlabels = ();
        my $inc = $datemin->clone;
        while($inc->epoch <= $datemax->epoch)
        {   push @xlabels, $self->_time_label($inc);
            $inc->add($x_time_step);
        }
    }
    elsif(!$x_axis) # Multiple columns, use column names
    {   @xlabels = map $_->name, @x;
    }
    elsif($self->trend)
    {   # Do nothing, already added
    }
    else
    {   @xlabels = sort keys %$results;
    }

    # Now that we have all the values retrieved and know the quantity
    # of the x-axis values, we can map these into individual series
    my $series;
    foreach my $serial (keys %$series_keys)
    {   foreach my $x ($x_axis ? @xlabels : @x)
        {
            my $x_val = $x_axis ? $x : $x->name;
            # May be a zero y-value for a grouped graph, but the
            # series still needs a zero written, even for a line graph.

            no warnings 'numeric', 'uninitialized';
            my $y = int $results->{$x_val}->{$serial};
            $y = 0 if !$x_axis && ! $x->is_numeric;
            push @{$series->{$serial}->{data}}, $y;
        }
    }

    if($graph->as_percent && $graph->type ne 'pie' && $graph->type ne 'donut')
    {   if($graph->group_by)
        {   my $any_series = (values %$series)[0];
            my $count = @{$any_series->{data}}; # Number of data points for each series

            for my $i (0..$count-1)
            {   my $sum = _sum( map $_->{data}[$i], values %$series );
                $_->{data}[$i] = _to_percent($sum, $_->{data}[$i])
                    for values %$series;
            }
        }
        else
        {   my $data = $series->{1}{data} ||= [];
            my $sum  = _sum @$data;
            @$data   = map _to_percent($sum, $_), @$data;
        }
    }

    # If this graph is measuring against a metric, recalculate against that
    my $metric_max;
    if (my $metric_group_id = $self->metric_group_id)
    {
        # Get set of metrics
        my @metrics = $::db->search(Metric => { metric_group => $metric_group_id })->all;
        my $metrics;

        # Put all the metrics in an easy to search hash ref
        foreach my $metric (@metrics)
        {   my $y_axis_grouping_value = $metric->y_axis_grouping_value || 1;
            $metrics->{$y_axis_grouping_value}{$metric->x_axis_value} = $metric->target;
        }

        # Now go into each data item and recalculate against the metric
        foreach my $line (keys %$series)
        {   my $data = $series->{$line}->{data};
            for my $i (0 .. $#$data)
            {   my $target  = $metrics->{$line}->{$xlabels[$i]};
                my $val     = $target ? int ($data->[$i] * 100 / $target ) : 0;
                $data->[$i] = $val;
                $metric_max = $val if !$metric_max || $val > $metric_max;
            }
        }
    }

    my @points; my @labels;
    if ($self->type eq 'pie' || $self->type eq 'donut')
    {
        foreach my $series (values %$series)
        {
            my $data = $series->{data};
            if($graph->as_percent)
            {   my $sum = _sum(@$data);
                $data   = [ map _to_percent($sum, $_), @$data ];
            }

            my $idx = 0;
            my @ps = map +[ encode_entities($_), ($data->[$idx++]||0) ], @xlabels;
            push @points, \@ps;
        }
        # XXX jqplot doesn't like smaller ring segment quantities first.
        # Length sorting fixes this, but should probably be fixed in jqplot.
        @points = sort { scalar @$b <=> scalar @$a } @points;
    }
    else
    {   # Work out the required jqplot labels for each series.

        my $markeroptions =
            $self->type eq 'scatter' ? '{ size: 7, style: "x" }' : '{ show: false }';

        foreach my $k (keys %$series)
        {   $series->{$k}{label} = {
                color         => $self->get_color($k),
                showlabel     => 'true',
                showline      => $self->type eq 'scatter' ? 'false' : 'true',
                markeroptions => $markeroptions,
                label         => $k,
            };
        }

        # Sort the names of the series so they appear in order on the
        # graph. For some reason, they need to be in reverse order to
        # appear correctly in jqplot.
        my @series = map $series->{$_}, reverse sort keys %$series;
        @points    = map $_->{data},  @series;
        @labels    = map $_->{label}, @series;
    }

    my %options;
    $options{y_max}     = 100 if defined $metric_max && $metric_max < 100;
    $options{is_metric} =   1 if defined $metric_max;

    # If we had a curval as a link, then we need to reset its retrieved fields,
    # otherwise anything else using the field after this procedure will be
    # using the reduced columns that we used for the graph
#XXX
    if($self->x_axis_link)
    {   $link->clear_curval_field_ids;
        $link->clear;
    }

    +{
        xlabels => \@xlabels, # Populated, but not used for donut or pie
        points  => \@points,
        labels  => \@labels, # Not used for pie/donut
        options => \%options,
    }
}

sub _records_to_results
{   my ($self, $records, %params) = @_;
    my $x_daterange  = $params{x_daterange};
    my $x            = $params{x};

    my $graph        = $self->graph;
    my $x_axis       = $graph->x_axis;
    my $x_axis_range = $graph->x_axis_range;
    my $y_axis       = $graph->y_axis;
    my $y_axis_stack = $graph->y_axis_stack;

    my $d2unit       = $self->_dt_format;

    my (%results, $series_keys, $datemin, $datemax);

    # If we have a specified x-axis range but only a date field, then we need
    # to pre-populate the range of x values. This is not needed with a
    # daterange, as when results are retrieved for a daterange it includes each
    # x-axis value in each row retrieved (dates only include the single value)

    if($x_axis_range && $x_axis->type eq 'date')
    {   foreach my $x (@$x)
        {   my $x_value = $dt_format->($x);
            $datemin //= $x_value; # First loop
            $datemax = $x_value if !defined $datemax || $datemax->epoch < $x_value->epoch;
            my $x_label = $self->_time_label($x_value);
            $results{$x_label} = {};
        }
    }

    # For each line of results from the SQL query
    my $records_results = $self->records->results;
    foreach my $line (@$records_results)
    {
        # For each x-axis point get the value.  For a normal graph this will be
        # the list of retrieved values. For a daterange graph, all of the
        # x-axis points will be datetime values.  For a normal date field with
        # a specified date range, we have already interpolated the points
        # (above) and we just need to get each individual value, not every
        # x-axis point (which will not be available in the results)
        my @for = $x_axis_range && $x_axis->type eq 'date' ? $x_axis : @$x;
        foreach my $x (@for)
        {
            my $col     = $x_daterange ? $x->epoch : $x->field;
            my $x_value = $line->get_column($col);
            $x_value  ||= $line->get_column("${col}_link")
                if !$x_daterange && $x->link_parent;

            $x_value = $self->_format_curcommon($x, $line)
                if !$x_daterange && $x->type eq 'curval' && $x_value;

            if(!$self->trend && $self->x_axis_time_units)
            {   # Group by date, round to required interval
                !$x_value and next;
                my $x_dt   = $x_daterange ? $x : $::db->parse_date($x_value);
                if(my $x_unit = $dt_format->($x_dt))
                {   $datemin = $x_unit if !defined $datemin || $datemin->epoch > $x_unit->epoch;
                    $datemax = $x_unit if !defined $datemax || $datemax->epoch < $x_unit->epoch;
                    $x_value = $self->_time_label($x_unit);
                }
            }
            elsif( !$x_axis )
            {   # Multiple column x-axis
                $x_value = $x->name;
            }

            $x_value ||= '<no value>';

            # The column name to retrieve from SQL record
            my $fname
              = $x_daterange ? $x->epoch
              : ! $x_axis    ? $x->field
              : $y_axis_stack eq 'count' ? 'id_count' # Don't use field count as NULLs are not counted
              :                $y_axis->field."_".$y_axis_stack;

            my $val = $line->get_column($fname);

            # Add on the linked column from another datasheet, if applicable
            my $include_linked = ! $x_axis && (!$x->is_numeric || !$x->link_parent); # Multi x-axis
            my $val_linked     = $y_axis_stack eq 'sum'
                && $y_axis->link_parent
                && $line->get_column("${fname}_link");

            no warnings 'numeric', 'uninitialized';
            if($params{values_only})
            {   $series_keys{$x_value} = 1;
                $results{$x_value} += $val + $val_linked;
            }
            else
            {   # The key for this series. May only be one (use "1")   #XXX?
                my $group_by = $graph->group_by;
                undef $group_by if $graph->type eq 'pie';  #XXX needed?

                my $k = $group_by && $group_by->is_curcommon
                              ? $self->_format_curcommon($group_by, $line)
                  : $group_by ? $line->get_column($group_by->field)
                  :             1;
                $k ||= $line->get_column($group_by->field."_link")
                    if $group_by && $group_by->link_parent;
                $k ||= '<blank value>';

                $series_keys{$k} = 1; # Hash to kill duplicate values

                # Store all the results for each x value together, by series
                $results{$x_value}{$k} += $val + $val_linked;
            }
        }
    }

    (\%results, \%series_keys, $datemin, $datemax);
}

=head2 my $csv_text = $data->csv;
=cut

sub csv()
{   my $self = shift;
    my $csv  = Text::CSV::Encoded->new({ encoding  => undef });

    my $rows;
    if ($self->type eq "pie" || $self->type eq "donut")
    {
        foreach my $ring (@{$self->points})
        {   my $count = 0;
            foreach (@$ring)
            {   my ($name, $value) = @$_;
                my $cell = $rows->[$count++] ||= [ $name ];
                push @$cell, $value;
            }
        }
    }
    else
    {   foreach my $series (@{$self->points})
        {   my $count = 0;
            foreach my $x (@{$self->xlabels})
            {   my $cell = $rows->[$count++] ||= [$x];
                push @$cell, shift @$series;
            }
        }
    }

    my @csvout;
    if($self->group_by)
    {   $csv->combine('', map $_->{label}, @{$self->labels});
        push @csvout, $csv->string;
    }

    foreach my $row (@$rows)
    {   $csv->combine(@$row);
        push @csvout, $csv->string;
    }

    join "\n", @csvout, '';
}

###
### Helpers
###

# Take a date and round it down according to the grouping
sub _dt_format
{   my $self = shift;
    my $units = $self->x_axis_time_units || '';

      $units eq 'year'
    ? sub { my $v = $_[0]; $v ? DateTime->new(year => $v->year) : undef }
    : $units eq 'month'
    ? sub { my $v = $_[0]; $v ? DateTime->new(year => $v->year, month => $v->month) : undef };
    : $units eq 'day'
    ? sub { my $v = $_[0]; $v ? DateTime->new(year => $v->year, month => $v->month, day => $v->day) : undef }
    : sub { $_[0] };
}

sub _time_label($)
{   my ($self, $date) = @_;
    static %dgf = (day => '%d %B %Y', month => '%B %Y', year  => '%Y');

    my $df = $dgf{$self->x_axis_time_units};
    $date->strftime($df);
}

sub _format_curcommon
{   my ($self, $column, $line) = @_;
    $line->get_column($column->field) or return;
    $column->format_value(map $line->get_column($_->field), @{$column->curval_fields});
}

sub _to_percent
{   my ($sum, $value) = @_;
    round(($value / $sum) * 100 ) + 0;
}

sub _sum { sum(map {$_ || 0} @_) }

sub _calculate_range
{   my $self  = shift;

    my $range = $self->x_axis_range
        or return;

    my $graph = shift->graph;
    my $time_units = $self->x_axis_time_units;

    my ($start, $end);

    if(my $from = $self->from)
    {   # If we are plotting a trend and have custom dates, round them down to
        # ensure correct sample set is plotted
        $start = $graph->trend
          ? $from->clone->truncate(to => $time_units)
          : $from->clone;
    }
    else
    {   # Either start now and move forwards or start in the past and move to now
        $start = DateTime->now->truncate(to => $time_units);
        $start->add(months => $range) if $range < 0;
        $start;
    }

    if(my $to = $self->to)
    {   $end = $self->trend
           ? $to->clone->truncate(to => $self->x_axis_time_units);
           : $to->clone;
    }
    else
    {   $end = $from->clone->add(months => abs $range);
    }

    ($start, $end);
}

1;
