=pod
GADS - Globally Accessible Data Store
Copyright (C) 2018 Ctrl O Ltd

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

package Linkspace::Render::Globe;

use GADS::RecordsGlobe;
use Log::Report 'linkspace';
use List::Util    qw/uniq/;
use MIME::Base64  qw/encode_base64/;
use JSON          qw/encode_json/;

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
use MooX::Types::MooseLike::DateTime qw/DateAndTime/;
extends 'Linkspace::Render';

my $default_marker = +{ size => 15, line => { width => 2 } };

=head1 METHODS: Attributes
Requires either C<selection> criteria or a page.
=cut

has group_col_id => ( is => 'ro');
has color_col_id => ( is => 'ro');
has label_col_id => ( is => 'ro');

has selection => (
    is       => 'ro',
    isa      => HashRef,
);

has page => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $search = $self->selection || {};
        $search->{max_results} //= 1000;
        $search->{group_values_as_index} = 0;
        $self->sheet->data->search($search);
    },
}

####
sub _parent($)
{   my ($self, $ref) = @_;
    my $parent = $ref =~ /^([0-9]+)_[0-9]+$/ ? $1 : return;
    $self->column($parent);
}

sub _child($)
{   my ($self, $ref) = @_;
    my $child = $ref =~ /^[0-9]+_([0-9]+)$/ ? $1 : $ref;
    $self->column($child);
}

has group_col => (
    is      => 'lazy',
    builder => sub { $_[0]->_child($_[0]->group_col_id) },
);

has group_col_parent => (
    is      => 'lazy',
    builder => sub { $_[0]->_parent($_[0]->group_col_id) },
);

sub has_group_col { !! $_[0]->group_col }

sub group_col_operator()
{   my $g = $_[0]->group_col;
    $g && $g->is_numeric ? 'sum' : 'max';
}

has color_col => (
    is      => 'lazy',
    builder => sub { $_[0]->_child($_[0]->color_col_id) },
);

has color_col_parent => (
    is      => 'lazy',
    builder => sub { $_[0]->_parent($_[0]->color_col_id) },
);

sub color_col_operator()
{   my $c = $_[0]->color_col;
    $c && $c->is_numeric ? 'sum' : 'max';
}

sub color_col_is_count() { $_[0]->color_col_id == -1 }
sub has_color_col() { $_[0]->color_col || $_[0]->color_col_is_count }

has label_col => (
    is      => 'lazy',
    builder => sub { $_[0]->_child($_[0]->label_col_id) },
);

has label_col_parent => (
    is      => 'lazy',
    builder => sub { $_[0]->_parent($_[0]->label_col_id) },
);

sub has_label_col()
{   my $self = shift;
    $self->label_col || ($self->label_col_id && $self->label_col_id < 0);
}

has is_choropleth => (
    is      => 'lazy'
    builder => sub {
    {   my $self = shift;
          ! $self->has_color_col    ? 0
        : $self->color_col_is_count ? 1 # Choropleth by record count
        : $self->color_col && $self->color_col->is_numeric;
    },
);

sub is_group()
{   my $self = shift;
    $self->has_color_col || $self->has_group_col || $self->has_label_col;
}

has _columns => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $columns = $self->page->columns_retrieved_no;
        my @curvals = map @{$_->curval_fields}, grep $_->is_curcommon, @$columns;
        [ @$columns, @curvals ];
   },
}

has _columns_globe => (
    is => 'lazy',
    builder => sub { [ grep $_->return_type eq 'globe', @{$self->_columns} ] },
);

has _used_color_keys => (
    is      => 'ro',
    default => sub { +{} },
);

has colors => (
    is => 'lazy',
);

sub _build_colors
{   my $self = shift;
    my $graph = $self->graph;
    [ map +{ key => $_, color => $graph->get_color($_) },
         keys %{$self->_used_color_keys} ];
}

has graph => (
    is => 'lazy',
);

# Need a Graph::Data instance to get relevant colors
sub _build_graph
{   my $self = shift;
    GADS::Graph::Data->new( records => undef,);
}

my %tosvg = qw/  > gt   < lt    & amp /;

sub _to_svg($)
{   my $s = shift;
    $s =~ s/([<>&])/\&${tosvg{$1}};/g;
    $s;
}

sub _legenda($)
{   my $lt = shift;
    join '<br>', map +($_ eq '_count' ? $lt->{$_} : "$_: $lt->{$_}"), keys %$lt;
}

sub data_ajax { encode_base64 encode_json($_[0]->data), '' }

sub data
{   my $self = shift;

    my $page   = $self->page;
    my $layout = $page->layout;

    # Add on any extra required columns for labelling etc
    my @extra;

    if(my $g = $self->group_col)
    {   push @extra, { col => $g, parent => $self->group_col_parent,
            operator => $self->group_col_operator, group => !$g->is_numeric };
    }

    if(my $c = $self->color_col)
    {   push @extra, { col => $c, parent => $self->color_col_parent,
            operator => $self->color_col_operator, group => !$c->is_numeric };
    }

    if(my $l = $self->label_col)
    {   push @extra, { col => $l, parent => $self->label_col_parent,
            group => !$l->is_numeric };
    }

    # Messier than it should be, but if there is no globe column in the view
    # and only one in the layout, then add it on, otherwise nothing will be
    # shown

    if($page->view)
    {   my %existing = map +($_->{col}->id => 1), @extra;
        push @extra, map +{ col => $_ }, grep !$existing{$_->id},
            @{$page->columns_view};

        my $gc = $layout->columns_search(is_globe => 1, user_can_read => 1);
        my $has_globe = first { $_->{col}->return_type eq 'globe' } @extra;
        push @extra, +{ col => $gc->[0], group => $self->is_group }
            if @$gc == 1 && !$has_globe;
    }
    else
    {   push @extra, map +{ col => $_ }, @{$layout->columns_search(user_can_read => 1)};
    }

    if($self->is_group)
    {   $_->{group} = 1 for grep $_->{col}->return_type eq 'globe', @extra;
    }

#XXX
    $page->columns( [ map +{
        id        => $_->{col}->id,
        parent_id => $_->{parent} && $_->{parent}->id,
        operator  => $_->{operator} || 'max',
        group     => $_->{group},
    }, @extra] );

    # All the data values
    my %countries;

    # Each row will be retrieved with each type of grouping if applicable
    while (my $record = $page->single)
    {
        if ($self->is_group)
        {
            my @this_countries;
            my ($value_color, $value_label, $value_group, $color);
            if ($self->has_color_col)
            {
                if ($self->color_col_is_count)
                {   $value_color = $record->get_column('id_count');
                }
                else
                {   my $field = $self->color_col->field;
                    $field .= "_sum" if $self->color_col_operator eq 'sum';
                    $value_color = $record->get_column($field);

                    if(!$self->color_col->is_numeric)
                    {   $color = $self->graph->get_color($value_color);
                        $self->_used_color_keys->{$value_color} = 1;
                    }
                }
            }

            if ($self->label_col)
            {   $value_label = $self->label_col->type eq 'curval'
                  ? $self->_format_curcommon($self->label_col, $record)
                  : $record->get_column($self->label_col->field);
                $value_label ||= '<blank>';
            }

            if ($self->group_col)
            {   my $field = $self->group_col->field;
                $field .= "_sum" if $self->group_col_operator eq 'sum';
                $value_group = $self->group_col->type eq 'curval'
                  ? $self->_format_curcommon($self->group_col, $record)
                  : $record->get_column($field) || '<blank>';
            }

            foreach my $column (@{$self->_columns_globe})
            {   my $country = $record->get_column($column->field);
                push @this_countries, $country if $country;
            }

            foreach my $this_country (@this_countries)
            {   push @{$countries{$this_country}}, {
                    id_count    => $record->get_column('id_count'),
                    value_color => $value_color,
                    color       => $color,
                    value_label => $value_label,
                    value_group => $value_group,
                };
            }
        }
        else
        {   my (@titles, @this_countries);
            foreach my $column (@{$self->_columns})
            {   my $d = $record->field($column->id) or next;

                # Only show unique items of children, otherwise will be a lot
                # of repeated entries
                next if $record->parent_id && !$d->child_unique;

                if($column->return_type eq 'globe')
                {   push @this_countries, $d->as_string;
                }
                elsif($column->type ne 'rag')
                {   push @titles, {col => $column, value => $d->as_string} if $d->as_string;
                }
            }

            foreach my $this_country (@this_countries)
            {   push @{$countries{$this_country}}, {
                    current_id => $record->current_id,
                    titles     => \@titles,
                };
            }
        }
    }

    my (@item_return, $seqnr);
    foreach my $country (keys %countries)
    {
        my $items = $countries{$country};

        my @colors;

        my $values;
        foreach my $item (@$items)
        {   my $group = $item->{value_group};

            # label
            if($self->has_label_col)
            {   if($self->label_col && $self->label_col->is_numeric)
                {   $values->{label_sum} += $item->{value_label} || 0;
                    push @{$values->{group_sums}}, { text => $group, sum => $item->{value_label} }
                        if $self->group_col;
                }
                else
                {   $values->{label_text}{$item->{value_label} || '_count'} += $item->{id_count};
                }
            }

            # color
            if ($self->has_color_col)
            {
                if ($self->is_choropleth)
                {   $values->{color_sum} += $item->{value_color} || 0;

                    # Add individual group totals, if not already added in previous label
                    push @{$values->{group_sums}}, { text => $group, sum => $item->{value_color} }
                        if $self->group_col && !($self->label_col && $self->color_col_id eq $self->label_col_id);
                }
                else
                {   $values->{color_text}{$item->{value_color}} += $item->{id_count};
                    $values->{color} = ! $values->{color} || $values->{color} eq $item->{color} ? $item->{color} : 'grey';
                }
            }

            # group
            if ($self->has_group_col)
            {   if($self->group_col->is_numeric)
                {   $values->{group_sum} += $group || 0;
                }
                else
                {   $values->{group_text}{$group} += $item->{id_count};
                }
            }

            # hover
            if (!$self->is_group)
            {
                my $t = join "", map {
                    '<b>' . $_->{col}->name . ':</b> '
                    . _to_svg($_->{value})
                    . '<br>'
                } grep $_->{col}->type ne 'file', @{$item->{titles}};

                $t = "<i>Record ID $item->{current_id}</i><br>$t" if @$items > 1;
                $values->{hover} ||= [];
                push @{$values->{hover}}, $t;
            }
        }

        # If we've grouped by a numeric value, then we will label/hover with
        # the information of how much is in each grouping
        my $group_sums = $values->{group_sums}
            && join('<br>', map _to_svg("$_->{text}: $_->{sum}"), @{$values->{group_sums}});

        # Hover will depend on the display options
        my $hover
          = $self->is_choropleth
          ? ($self->group_col ? $group_sums : "Total: $values->{color_sum}")
          : $self->label_col && $self->label_col->is_numeric
          ? ($self->group_col ? $group_sums : "Total: $values->{label_sum}")
          : $self->color_col  ? _legenda($values->{color_text})
          : $self->group_col
          ? ( $self->group_col->is_numeric
            ? "Total: $values->{group_sum}"
            : _legenda($values->{group_text})
            )
          : $self->has_label_col ? _legenda($values->{label_text})
          : join('<br>', @{$values->{hover}});

        # Only add a label if selected by user
        my $label
           = ! $self->has_label_col ? undef
           : $self->label_col && ! $self->label_col->is_numeric
           ? _legenda($values->{label_text})
           : $self->group_col       ? $group_sums
           :                          $values->{label_sum};

        push @item_return, +{
            hover    => $hover,
            location => $country,
            index    => $self->color_col ? ++$seqnr : 1,
            color    => $values->{color},
            z        => $values->{color_sum},
            label    => $label,
        };
    }

    @item_return || @{$self->_columns_globe}
        or mistake __"There are no globe fields in this view to display";

    my $country_colors
      = $self->is_choropleth ? undef
      : $self->color_col     ? [ map $_->{color}, @item_return ]
      : [ ('#D3D3D3') x @item_return ];

    my @return = +{
        z            => [ map $_->{z},        @item_return ],
        text         => [ map $_->{hover},    @item_return ],
        locations    => [ map $_->{location}, @item_return ],
        showscale    => $self->is_choropleth ? \1 : \0,
        type         => $self->is_group ? 'choropleth' : 'scattergeo',
        hoverinfo    => 'text',
        locationmode => 'country names',
        countrycolors => $country_colors,
        ($self->is_group ? () : (marker => $default_marker)),
    };

    if ($self->has_label_col) # Add as second trace
    {   # Need to add a hover as well, otherwise there is a dead area where the
        # hover doesn't appear
        push @return, +{
            text         => [ map $_->{label},    @item_return ],
            locations    => [ map $_->{location}, @item_return ],
            hovertext    => [ map $_->{hover},    @item_return ],
            hoverinfo    => 'text',
            mode         => 'text',
            type         => 'scattergeo',
            locationmode => 'country names',
        };
    }

    \@return;
}

sub uniq_join { join ', ', uniq @_ }

sub _format_curcommon
{   my ($self, $column, $line) = @_;
    my $text = $column->format_value(map $line->get_column($_->field), @{$column->curval_fields});
    qq(<a href="/record/$id">$text</a>);
}

1;

