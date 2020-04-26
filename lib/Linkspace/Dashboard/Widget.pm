=pod
GADS - Globally Accessible Data Store
Copyright (C) 2017 Ctrl O Ltd

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

package Linkspace::Dashboard::Widget;

use Log::Report 'linkspace';

use Linkspace::Dashboard::Widget::Globe;
use Linkspace::Dashboard::Widget::Timeline;

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
extends 'Linkspace::DB::Table';

sub db_table { 'Widget' }

sub db_field_rename { +{
    static        => 'is_static',
    tl_options    => 'tl_options_json',
    globe_options => 'glob_options_json',
} }

### 2020-04-24: columns in GADS::Schema::Result::Widget
# id            dashboard_id  h             view_id
# title         globe_options rows          w
# type          graph_id      static        x
# content       grid_id       tl_options    y

my %type2class = qw/
    globe    Linkspace::Dashboard::Widget::Globe
    graph    Linkspace::Dashboard::Widget
    notice   Linkspace::Dashboard::Widget
    table    Linkspace::Dashboard::Widget
    timeline Linkspace::Dashboard::Widget::Timeline
/;

=head1 NAME

Linkspace::Dashboard::Widget - base for widgets

=head1 DESCRIPTION
Part of a Dashboard.

=head1 METHODS: Constructors
=cut

has view => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $view_id = $self->view_id;
        my $sheet   = $self->dashboard->sheet or panic;
        $sheet->views->view($self->view_id);
    },
);

sub from_record($%)
{   my ($class, $record) = (shift, shift);
    my $impl = $type2class{$record->{type}} or panic;
    $impl->SUPER::from_record($record, @_);
}

sub validate($)
{   my ($self, $update) = @_;

    if(my $view = delete $update->{view})
    {   $update->{view_id} = $view->id;
    }

    if(my $graph = delete $update->{graph})
    {   $update->{graph_id} = $graph->id;
    }

    if(my $tl = delete $update->{tl_options};
    {   $update->{tl_options_json} = ref $tl eq 'HASH' : encode_json $tl : $tl;
    }

    if(my $gl = delete $update->{globe_options};
    {   $update->{globe_options_json} = ref $gl eq 'HASH' : encode_json $gl : $gl;
    }
}

sub widget_create($)
{   my ($class, $insert) = @_;

    # collission inplausible
    $insert->{grid_id} ||= Session::Token->new(length => 32)->get;

    my $impl = $type2class{$insert->{type}} or panic;
    $impl->create($class->validate($insert));
}

sub widget_update($)
{   my ($self, $update) = @_;
    delete $update->{type};
    $self->create($class->validate($update));
}

#------------------
=head1 METHODS: Accessors
=cut

has dashboard => (
    is       => 'ro',
    required => 1,
    weakref  => 1,
);

sub tl_options
{   my $opts = $_[0]->tl_options_json;
    $opts ? decode_json $opts : undef;
}

sub globe_options
{   my $opts = $_[0]->globe_options_json;
    $opts ? decode_json $opts : undef;
}

sub before_create
{   my $self = shift;
    if (!$self->grid_id)
    {
        # Potential race condition, but unlikely and unique constrant will
        # catch anyway
        my $grid_id;
        my $existing = $::db->search(Widget => {
            dashboard_id => $self->dashboard_id,
        });
        while (!$grid_id || $existing->search({ grid_id => $grid_id })->count)
        {
            $grid_id = Session::Token->new( length => 32 )->get;
        }
        $self->grid_id($grid_id);
    }
}


sub html
{   my $self = shift;

    my $params = {
        type  => $self->type,
        title => $self->title,
    };

    if($self->type eq 'notice')
    {   $params->{content} = $self->content;
    }
    else
    {
        my $view = $self->view;

        if ($self->type eq 'table')
        {   my $page = $view->search(
                page   => 1,
                rows   => $self->rows,
                #rewind => session('rewind'), # Maybe add in the future
            );

            my @columns =  map $_->presentation(sort => $page->sort_first),
                @{$page->columns_view};

            $params->{records} = $page->presentation;
            $params->{columns} = \@columns;
        }
        elsif ($self->type eq 'graph')
        {
            my $records = GADS::RecordsGraph->new(
                layout  => $layout,
            );

            my $gdata = GADS::Graph::Data->new(
                id      => $self->graph_id,
                records => $records,
                view    => $view,
            );

            my $plot_data = encode_base64 $gdata->as_json, ''; # base64 plugin does not like new lines in content $gdata->as_json;
            my $graph = GADS::Graph->new(
                id     => $self->graph_id,
                layout => $layout,
            );

            $params->{graph_id}     = $self->graph_id;
            $params->{plot_data}    = $plot_data;
            $params->{plot_options} = encode_base64 $graph->legend_as_json, '';
        }
        elsif ($self->type eq 'timeline')
        {
            my $records = $view->search(
                # No "to" - will take appropriate number from today
                from                => DateTime->now, # Default
            );
            my $tl_options = $self->tl_options_inflated;
            my $timeline = $records->data_timeline(%{$tl_options});

            $params->{records}      = encode_base64(encode_json(delete $timeline->{items}), '');
            $params->{groups}       = encode_base64(encode_json(delete $timeline->{groups}), '');
            $params->{click_to_use} = 1;
            $params->{timeline}     = $timeline;
        }
        elsif ($self->type eq 'globe')
        {
            my $globe_options = $self->globe_options_inflated;
            my $globe = GADS::Globe->new(
                group_col_id    => $globe_options->{group},
                color_col_id    => $globe_options->{color},
                label_col_id    => $globe_options->{label},
                records_options => {
                    view   => $view,
                    layout => $layout,
                },
            );
            $params->{globe_data} = encode_base64(encode_json($globe->data), '');
        }
    }

    my $config = GADS::Config->instance;
    my $template = Template->new(INCLUDE_PATH => $config->template_location);

    my $output;
    my $t = $template->process('snippets/widget_content.tt', $params, \$output)
        or panic $template->error;

    $output;
}

sub to_ajax
{   my $self = shift;
    +{
        html => $self->html,
        grid => encode_json {
            i      => $self->grid_id,
            static => !$self->is_shared && $self->static ? \1 : \0,
            h      => $self->h,
            w      => $self->w,
            x      => $self->x,
            y      => $self->y,
        },
     };
}

sub for_sheet($)
{   my ($self, $other_sheet) = @_;
    my $my_sheeet = $self->dashboard->sheet;
      ! defined $other_sheet ? !defined $my_sheet
    : ! defined $my_sheet    ? 0
    : $my_sheet->id == $other_sheet->id;
}

1;
