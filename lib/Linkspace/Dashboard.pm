## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Dashboard;

use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
extends 'Linkspace::DB::Table';

sub db_table { 'Dashboard' }

sub db_field_rename { +{
    user_id => 'owner_id',
} };

#XXX Later changes give this table a site_id
### 2020-04-24: columns in GADS::Schema::Result::Dashboard
# id  instance_id user_id

=head1 NAME

Linkspace::Dashboard - a website page of widgets

=head1 DESCRIPTION
The Dashboard is a configurable display component, which manages Widgets.
The dashboard may be sheet related, but there is also one connected to the Site.

=head1 METHODS: Constructors
=cut

sub delete()
{   my $self = shift;
    $::db->delete(Widget => { dashboard_id => $self->id });
    $self->SUPER::delete;
}

=head1 METHODS: Accessors
=cut

sub owner
{   my $self = shift;
    my $user_id = $self->owner_id or return;
    $self->site->users->user($user_id);
}

sub is_shared { ! $_[0]->owner_id }
sub is_empty  { ! keys %{$_[0]->_widget_index} }

sub name
{   my $self = shift;
    my $name  = $self->sheet ? $self->sheet->name : 'Site';
    my $owned = $self->owner_id ? 'personal' : 'shared';
    "$name dashboard ($owned)";
}

sub url
{   my $self = shift;
    my $ident = $self->sheet ? $self->sheet->identifier : '';
    "/$ident?did=".$self->id;
}
sub download_url { $_[0]->url . '&download=pdf' }

sub can_write(;$)
{   my ($self, $user) = @_;
    $user ||= $::session->user;
    return 1 if +($self->owner_id //0) == $user->id;

    my $sheet = $self->sheet;
    $sheet && $sheet->user_can(layout => $user);
}

#-------------------------
=head1 METHODS: Manage Widgets

=head2 \@widgets = $dashboard->static_widgets;
Returns all widgets which are shown always.
=cut

has _widget_index => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $sheet_id = $self->sheet ? $self->sheet->id : undef;
        my @records  = $::db->search(Widget =>
          { 'dashboard.instance_id' => $sheet_id },
          { join => 'dashboard' })->all;
        +{ map +($_->id => $_, $_->grid_id => $_), @records;
    },
);

sub widget($)
{   my ($self, $which) = @_;  # $which is id or grid_id
    return $which if blessed $which;

    my $record = $self->_widget_index->{$which};
    blessed $record ? $record
    : Linkspace::Dashboard::Widget->from_record($record, dashboard => $self);
}

sub widget_create($)
{   my ($self, $insert) = @_;
    my $type      = $insert->{type} or panic;

    # collission inplausible
    my $widget_id = Linkspace::Dashboard::Widget->widget_create($insert);
    my $widget    = $impl->from_id($widget_id, dashboard => $self);

    my $index     = $self->_widget_index;
    $index->{$widget_id} = $index->{$widget->grid_id} = $widget;
}

sub widget_update($)
{   my ($self, $widget, $update) = @_;
    $widget->widget_update($update);
}

sub widget_delete($)
{   my ($self, $widget) = @_;
    my $index = $self->_widget_index;
    delete $index->{$widget->id};
    delete $index->{$grid_id};
    $widget->delete;
}

sub static_widgets
{   my $self = shift;
    my @all_static = grep $_->is_static, values %{$self->_widget_index};

    my $sheet  = $self->sheet;
    [ grep $_->for_sheet($sheet), map $self->widget(@all_static) ];
}

sub private_widgets(;$)
{   my ($self, $user) = @_;
    my $user_id = ($user || $::session->user)->id;
    my @owned   = grep +($_->user_id//0) == $user_id, values %{$self->_widget_index};

    my $sheet  = $self->sheet;
    [ grep $_->for_sheet($sheet), map $self->widget(@owned) ];
}

sub display_widgets
{   my $self = shift;
    my $statics = $self->is_shared ? [] : $self->static_widgets;
    [ map $_->to_ajax($_), @$statics, @{$self->private_widgets} ];
}

sub as_json
{   my $self = shift;
    encode_json {
        name         => $self->name,
        download_url => $self->download_url,
    };
}

1;
