## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::AlertSend;

use List::MoreUtils qw/ uniq /;
use Log::Report 'linkspace';
use Scalar::Util qw(looks_like_number);

use Moo;
use MooX::Types::MooseLike::Base qw(:all);
use namespace::clean;

has current_ids => (
    is       => 'rw',
    isa      => ArrayRef,
    required => 1,
);

# Whether this is a brand new record
has current_new => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has base_url => (
    is => 'lazy',
);

sub _build_base_url
{   my $self = shift;
    my $config = GADS::Config->instance;
    $config->gads->{url}
        or panic "URL not configured in application config";
}

has columns => (
    is       => 'rw',
    required => 1,
);

sub process
{   my $self = shift;
    my $sheet = $self->sheet;

    # First the direct layout
    $self->_process_instance($sheet, $self->current_ids);
    my $site = $self->site;

    # Now see if the column changes in this layout may have changed views in
    # other layouts.
    # First, are there any views not in the main layout that contain these fields?
    my @sheet_ids = $::db->search(View => {
        'alerts.id'         => { '!=' => undef },
        instance_id         => { '!=' => $sheet->id},
        'filters.layout_id' => $self->columns,
    },{
        join     => ['alerts', 'filters'],
        group_by => 'me.instance_id',
    })->get_column('instance_id')->all;

    # If there are, process each one
    foreach my $sheet_id (@sheet_ids)
    {   my $sheet  = $site->sheet($sheet_id);

        # Get any current IDs that may have been affected, including historical
        # versions (in case a filter has been set using previous values)
        my @current_ids = $::db->search(Curval => {
            'layout.instance_id' => $sheet_id,
            value                => $self->current_ids,
        }, {
            join     => ['layout', 'record'],
            group_by => 'record.current_id',
        })->get_column('record.current_id')->all;

        $self->_process_instance($sheet, \@current_ids);
    }
}

sub _process_instance
{   my ($self, $sheet, $current_ids) = @_;

    # First see what views this record should be in. We use this to see if it's
    # dropped out or been added to any views.

    # Firstly, search on the views that may have been affected. This is all the
    # ones that have a filter with the changed columns. If this is a brand new
    # record, however, then it doesn't matter what columns have changed, so get
    # all the views.
    my %search = (
        'alerts.id' => { '!=' => undef },
        instance_id => $sheet->id,
    );
    $search{'filters.layout_id'} = $self->columns
        unless $self->current_new;

    my @view_ids = $::db->search(View => \%search, {
        join     => ['alerts', 'filters'],
    })->get_column('id')->all;

    # We now have all the views that may have been affected by this update.
    # Convert them into GADS::View objects
    my $views = GADS::Views->new(
        # Current user may not have access to all fields in view,
        # permissions are managed when sending the alerts
        user_permission_override => 1,
    );

    my $records = GADS::Records->new(
        columns => [], # Otherwise all columns retrieved during search construct
        user    => $self->user,
    );

    my @to_add; # Items to add to the cache later
    if (my @views = map $views->view($_), @view_ids)
    {
        # See which of those views the new/changed records are in.
        #
        # All the views the record is *now* in
        my $now_in_views; my $now_in_views2;
        foreach my $now_in ($records->search_views($current_ids, @views))
        {
            # Create an easy to search hash for each view, user and record
            my $view_id = $now_in->{view}->id;
            my $user_id = $now_in->{user_id} || '';
            my $cid     = $now_in->{id};

            $now_in_views->{$view_id}{$user_id}{$cid} = 1;
            # The same, in a slightly different format
            $now_in_views2->{"${view_id}_${user_id}_${cid}"} = $now_in;
        }

        # Compare that to the cache, so as to find the views that the record *was*
        # in. Chunk the searches, otherwise we risk overrunning the allowed number
        # of search queries in the database
        my $i = 0; my @original;
        # Only search on views we know may have been affected, as per records search
        my %search = ( 'view.id' => \@view_ids );
        while ($i < @$current_ids)
        {
            # If the number of current_ids that we have been given is the same as the
            # number that exist in the database, then assume that we are searching
            # all records. Therefore don't specify (the potentially thousands) current_ids.
            if(@$current_ids != $records->count)
            {   my $max = $i + 499;
                $max = @$current_ids -1 if $max >= @$current_ids;
                $search{'me.current_id'} = [ @$current_ids[$i..$max] ];
            }

            push @original, $::db->search(AlertCache => \%search, {
                select => [
                    { max => 'me.current_id' },
                    { max => 'me.user_id' },
                    { max => 'me.view_id' },
                ],
                as => [qw/
                    me.current_id
                    me.user_id
                    me.view_id
                /],
                join     => 'view',
                group_by => ['me.view_id', 'me.user_id', 'me.current_id'], # Remove column information
                order_by => ['me.view_id', 'me.user_id', 'me.current_id'],
            })->all;
            last unless $search{'me.current_id'}; # All current_ids
            $i += 500;
        }

        # Now go through each of the views/alerts that the records *were* in, and
        # work out whether the record has disappeared from any.
        my @gone;
        foreach my $alert (@original)
        {
            # See if it's still in the views. We use the previously created hash
            # that contains all the views that the records are now in.
            my $view_id = $alert->view_id;
            my $user_id = $alert->user_id || '';
            my $cid     = $alert->current_id;
            if (!$now_in_views->{$view_id}{$user_id}{$cid})
            {
                # The row we're processing doesn't exist in the hash, so it's disappeared
                my $view = $views->view($view_id);
                push @gone, {
                    view       => $view,
                    current_id => $cid,
                    user_id    => $user_id,
                };

                $::db->delete(AlertCache => {
                    view_id    => $view_id,
                    user_id    => $user_id,
                    current_id => $cid,
                });
            }
            else
            {   # The row we're processing does appear in the hash, so no change. Flag
                # this in our second cache. Anything left in the second hash is therefore
                # something that is new in the view.
                delete $now_in_views2->{"${view_id}_${user_id}_${cid}"};
            }
        }

        # Now see what views it is new in, using the second hash
        my @arrived;
        foreach my $item (values %$now_in_views2)
        {
            my $view = $item->{view};

            push @to_add, {
                user_id    => $item->{user_id},
                view_id    => $view->id,
                layout_id  => $_,
                current_id => $item->{id},
            } for @{$view->column_ids};

            # Add it to a hash suitable for emailing alerts with
            push @arrived, {
                view        => $view,
                user_id     => $item->{user_id},
                current_id  => $item->{id},
            };
        }

        # Send the gone and arrived notifications
        $self->_gone_arrived('gone', @gone);
        $self->_gone_arrived('arrived', @arrived);
    }

    # Now find out which values have changed in each view. We simply take the list
    # of changed columns and records, and search the cache.
    my $i = 0; my @caches;
    my $search = {
        'alert_caches.layout_id' => $self->columns, # Columns that have changed
        'me.instance_id'         => $sheet->id,
    };
    while ($i < @$current_ids)
    {
        # See above comments about searching current_ids
        if(@$current_ids != $records->count)
        {   my $max = $i + 499;
            $max = @$current_ids-1 if $max >= @$current_ids;
            $search->{'alert_caches.current_id'} = [@$current_ids[$i..$max]];
        }
        push @caches, $::db->search(View => $search, {
            prefetch => ['alert_caches', {alerts => 'user'} ],
        })->all;
        last unless $search->{'alert_caches.current_id'}; # All current_ids
        $i += 500;
    }

    # We now have a list of views that have changed
    foreach my $view (@caches)
    {
        # We iterate through each of the alert's caches, sending alerts where required
        my $send_now; # Used for immediate send to amalgamate columns and IDs
        foreach my $alert_cache ($view->alert_caches)
        {
            my $col_id = $alert_cache->layout_id;
            my @alerts = $alert_cache->user ? $::db->search(Alert => {
                view_id => $alert_cache->view_id,
                user_id => $alert_cache->user_id,
            })->all : $alert_cache->view->alerts;

            my $layout = $sheet->layout;
            foreach my $alert (@alerts)
            {
                # For each user of this alert, check they have read access
                # to the field in question, and send accordingly
                next unless $layout->column($col_id)->user_id_can($alert->user_id, 'read');
                if ($alert->frequency) # send later
                {
                    my $write = {
                        alert_id   => $alert->id,
                        layout_id  => $col_id,
                        current_id => $alert_cache->current_id,
                        status     => 'changed',
                    };
                    # Unique constraint. Catch any exceptions. This is also
                    # why we probably can't do all these with one call to populate()
                    try { $::db->create(AlertSend => $write) };
                    # Log any messages from try block, but only as trace
                    $@->reportAll(reason => 'TRACE');
                }
                else
                {   my $send = $send_now->{$alert->user_id} ||= {
                        user    => $alert->user,
                        cids    => [],
                        col_ids => [],
                    };
                    push @{$send->{col_ids}}, $col_id;
                    push @{$send->{cids}}, $alert_cache->current_id;
                }
            }
        }

        my $layout = $sheet->layout;
        foreach my $a (values %$send_now)
        {
            $self->_send_alert(changed =>
               $a->{cids}, $view, [ $a->{user}->email ],
               [ map $layout->column($_)->name, @{$a->{col_ids}} ],
            );
        }
    }

    # Finally update the alert cache. We don't do this earlier, otherwise a new
    # record will be flagged as a change.
    $::db->resultset('AlertCache')->populate(\@to_add) if @to_add;
}

sub _gone_arrived
{   my ($self, $action, @items) = @_;

    foreach my $item (@items)
    {
        my @emails;
        foreach my $alert ($item->{view}->all_alerts)
        {
            if ($alert->frequency)
            {
                # send later
                try {
                    # Unique constraint on table. Catch
                    # any exceptions
                    $::db->create(AlertSend => {
                        alert_id   => $alert->id,
                        current_id => $item->{current_id},
                        status     => $action,
                    });
                };
                # Log any messages from try block, but only as trace
                $@->reportAll(reason => 'TRACE');
            }
            else {
                # send now
                push @emails, $alert->user->email;
            }
        }
        $self->_send_alert($action, [$item->{current_id}], $item->{view}, \@emails) if @emails;
    }
}

sub _current_id_links
{   my ($base, @current_ids) = @_;
    my @links = map { qq(<a href="${base}record/$_">$_</a>) } @current_ids;
    wantarray ? @links : $links[0];
}

sub _send_alert
{   my ($self, $action, $current_ids, $view, $emails, $columns) = @_;

    my $view_name = $view->name;
    my @current_ids = uniq @{$current_ids};
    my $base = $self->base_url;

    my ($text, $html);
    my $ids      = join ', ', @current_ids;
    my $ids_html = _current_id_links($base, @current_ids);

    # There sometimes is an extra \n go get an additional blank line.  This
    # makes it a but more readible.

    if($action eq "changed")
    {   my $cnames   = join ', ', uniq @$columns; # Individual fields to notify

        if(@current_ids > 1)
        {   ($text, $html) = (<<__TEXT, <<__HTML);
The following items were changed for record IDs $ids: $cnames\n
Links to the records are as follows:
__TEXT
<p>The following items were changed for record IDs $ids_html: $cnames</p>
__HTML
        }
        else
        {   ($text, $html) = ( <<__TEXT, <<__HTML );
The following items were changed for record ID $ids: $cnames\n
Please use the following link to access the record:
__TEXT
<p>The following items were changed for record ID $ids_html: $cnames</p>
__HTML
        }
    }

    elsif($action eq "arrived")
    {   if (@current_ids > 1)
        {   ($text, $html) = ( <<__TEXT, <<__HTML );
New items have appeared in the view "$view_name", with the following IDs: $ids\n
Links to the new items are as follows:
__TEXT
<p>New items have appeared in the view "$view_name", with the following IDs: $ids_html</p>
__HTML
        }
        else
        {   ($text, $html) = ( <<__TEXT, <<__HTML );
A new item (ID $ids) has appeared in the view "$view_name".\n
Please use the following link to access the record:
__TEXT
(A new item (ID $ids_html) has appeared in the view "$view_name".</p>
__HTML
        }
    }

    elsif($action eq "gone")
    {   if(@current_ids > 1)
        {   ($text, $html) = ( <<__TEXT, <<__HTML );
Items have disappeared from the view "$view_name", with the following IDs: $ids\n
Links to the removed items are as follows:
__TEXT
<p>Items have disappeared from the view "$view_name", with the following IDs: $ids_html</p>
__HTML
        }
        else
        {   ($text, $html) = ( <<__TEXT, <<__HTML );
An item (ID $ids) has disappeared from the view "$view_name".\n
Please use the following link to access the original record:
__TEXT
<p>An item (ID $ids_html) has disappeared from the view "$view_name"</p>
__HTML
        }
    }

    $text  .= map "${base}record/$_\n", @current_ids;

    $::linkspace->mailer->send(
        subject => qq(Changes in view "$view_name"),
        emails  => $emails,
        text    => $text,
        html    => $html,
    );
}

1;
