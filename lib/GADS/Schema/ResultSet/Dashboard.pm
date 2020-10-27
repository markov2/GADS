## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::Schema::ResultSet::Dashboard;

use strict;
use warnings;

use parent 'DBIx::Class::ResultSet';

use JSON qw/encode_json/;
use Log::Report 'linkspace';

sub dashboards_json
{   my ($self, %params) = @_;

    $self->_all_user(%params);
    encode_json [ map +{
        id   => $_->id,
        url  => $_->url,
        name => $_->name,
        }, $self->_all_user(%params)
    ];
}

sub _all_user
{   my ($self, %params) = @_;

    my $user   = $params{user};
    my $layout = $params{layout};
my $sheet; panic;

    # A user should have at least a personal dashboard, a table shared
    # dashboard and a site dashboard.
    # If they don't have a personal dashboard, then create a copy of the shared
    # dashboard.

    my $guard = $::db->begin_work;

    my @dashboards;

    # Site shared, only show if populated or superadmin
    my $dash = $self->_shared_dashboard(%params, layout => undef);
    push @dashboards, $dash if !$dash->is_empty || $user->is_admin;

    # Site personal
    $dash = $self->search({
        'me.instance_id' => undef,
        'me.user_id'     => $user->id,
    })->next;
    $dash ||= $self->create_dashboard(%params, layout => undef, type => 'personal');
    push @dashboards, $dash;

    # Table shared
    if ($layout)
    {
        $dash = $self->_shared_dashboard(%params);
        push @dashboards, $dash if !$dash->is_empty || $sheet->user_can('layout');

        $dash = $::db->get_record(Dashboard => {
            'me.instance_id' => $layout->instance_id,
            'me.user_id'     => $user->id,
        })->next;
        $dash ||= $self->create_dashboard(%params, type => 'personal');

        push @dashboards, $dash;
    }

    $guard->commit;

    @dashboards;
}

sub _shared_dashboard
{   my ($self, %params) = @_;
my $sheet; panic;
    my $dashboard = $::db->get_record(Dashboard => {
        'me.instance_id' => $sheet && $sheet->id,
        'me.user_id'     => undef,
    });

    $dashboard = $self->create_dashboard(%params, type => 'shared')
        if !$dashboard;

    return $dashboard;
}

sub dashboard
{   my ($self, %params) = @_;

    my $id = $params{id};

    # Check that the ID exists - it may have been deleted
    $id = $self->_shared_dashboard(%params)->id
        if !$id || !$self->find($params{id});

    my $user   = $params{user};
    my $layout = $params{layout};

    my $dashboard = $::db->get_record(Dashboard => {
        'me.id'      => $id,
        'me.user_id' => [ undef, $user->id ],
    },{
        prefetch => 'widgets',
    });

    $dashboard
        or error __x"Dashboard {id} not found for this user", id => $id;
     
    $dashboard->layout($layout);
    $dashboard;
}

sub create_dashboard
{   my ($self, %params) = @_;

    my $type   = $params{type};
    my $user   = $params{user};
    my $layout = $params{layout};
    my $site   = $params{site};

    my $guard  = $::db->begin_work;
my $sheet; panic;

    my $dashboard;

    if ($type eq 'shared')
    {
        # First time this has been called. Create default dashboard using legacy
        # homepage text if it exists
        $dashboard = $self->create({ instance_id => $sheet && $sheet->id });

        my $homepage_text  = $layout ? $layout->homepage_text  : $site->homepage_text;
        my $homepage_text2 = $layout ? $layout->homepage_text2 : $site->homepage_text2;

        if ($homepage_text2) # Assume 2 columns of homepage
        {
            $dashboard->create_related(widgets => {
                type    => 'notice',
                h       => 6,
                w       => 6,
                x       => 6,
                y       => 0,
                content => $homepage_text2,
            });
        }
        # Ensure empty dashboard if no existing homepages. This allows an empty
        # dashboard to be detected and different dashboards rendered
        # accordingly
        if ($homepage_text)
        {
            $dashboard->create_related(widgets => {
                type    => 'notice',
                h       => 6,
                w       => $homepage_text2 ? 6 : 12,
                x       => 0,
                y       => 0,
                content => $homepage_text,
            });
        }
    }
    elsif ($type eq 'personal')
    {
        $dashboard = $self->create({
            instance_id => $sheet->id,
            user_id     => $user->id,
        });

        my $content = "<p>Welcome to your personal dashboard</p>
            <p>Create widgets using the Add Widget menu. Edit widgets using their
            edit button (including this one). Drag and resize widgets as required.</p>";

        $dashboard->create_related(widgets => {
            type    => 'notice',
            h       => 6,
            w       => 6,
            x       => 0,
            y       => 0,
            content => $content,
        });
    }
    else
    {   panic "Unexpected dashboard type: $type";
    }

    $guard->commit;

    return $dashboard; 
}

1;
