## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::View::Alert;

use List::MoreUtils qw/uniq/;
use Log::Report     'linkspace';

use Moo;
extends 'Linkspace::DB::Table';

sub db_table { 'Alert' }

sub db_fields_rename { +{
    user_id => 'owner_id',
}; }

### 2020-05-11: columns in GADS::Schema::Result::Alert
# id         user_id    frequency  view_id

has view => (
    is       => 'ro',
    weakref  => 1,
    required => 1,
);

=head1 METHODS: Constructors

=head2 my $alert = $class->current($view, $user?, %options)
Returns the latest alert object for the C<$user>.
=cut

sub current($$%)
{   my ($class, $view, $whose) = (shift, shift, shift);
    $whose ||= $::session->user;
    $class->from_search({view => $view, owner => $whose}, @_);
}

sub for_user($%)
{   my ($class, $user, %args) = @_;
    $class->search_objects({user => $user}, {}, %args);
}

sub _alert_validate($)
{   my ($self, $changes) = @_;

    if(exists $changes->{frequency})
    {   my $freq = $changes->{frequency};
        $freq =~ /^([0-9]+)$/
            or error __x"Frequency value '{freq}' invalid", freq => $freq;
           
        $freq==0 || $freq==24
            or error __x"Frequency value '{freq}' unsupported", freq => $freq;
    }
}

sub _alert_create($%)
{   my ($class, $insert) = (shift, shift);
    $class->create($insert, @_);
}

sub _alert_update($)
{   my ($self, $update) = @_;
    if($update{frequency})
}

sub _alert_delete()
{   my ($self) = @_;
    my $view = $self->view;

    if(@{$view->all_alerts} == 1)
    {   # Clean-up some mess, when everyone has cleaned their alerts
        #XXX needed?
        $::db->delete(AlertSend => { alert_id => $self->id });
        $::db->delete(AlertCache => { view_id => $view->id });
    }
    $self->delete;
}

#--------------------
=head1 METHODS: Manage alert cache
=cut

sub update_cache($)
{   my ($self, %options) = @_;
    my $view = $self->view;

    # If the view contains a CURUSER filter, we need separate
    # alert caches for each user that has this alert. Only need
    # to worry about this if all_users flag is set
    my @users = $view->has_curuser && $options{all_users}
      ? $self->search_objects({ view => $view })
      : $::session->user;

    foreach my $user (@users)
    {   my $u = $view->has_curuser ? $user : undef;
        my $user_id = $u ? $u->id : undef;

        my $page = $sheet->search(view => $view);

        my %keep;
        # For each item in this view, see if it exists in the cache. If it
        # doesn't, create it.
        # Wrap in a LR try block so that we can disard the thousands of trace
        # messages that are generated during record retrieval, otherwise this
        # function will use a lot of memory. Only collect messages at warning
        # or higher and then report on completion.
        my $view_column_ids = $view->column_ids;
        try {
            while(my $record = $page->row_next)
            {   my $a = {
                    view_id    => $view->id,
                    current_id => $record->current_id,
                    user_id    => $user_id,
                };

                foreach my $column_id (@$column_ids})
                {   $a->{layout_id} = $column_id;

                    my $cached = $::db->get_record(AlertCache => $a)
                       || $::db->create(AlertCache => $a);

                    $keep{$cached->id}++;
                }
            }
        } accept => 'WARNING-';
        $@->reportFatal;

        # Delete all unused cached
        my $rs = $::db->search(AlertCache => {
            view_id => $view->id,
            user_id => $user_id,
        });

        while(my $chached = $rs->next)
        {   $keep{$chached->id} or $cached->delete;
        }
    }

    # Now delete any alerts that should not be there that are applicable to our update
    if($view->has_curuser)
    {
        # Possibly just changed to curuser, cleanup any
        # undef user rows from previous alert
        $::db->delete(AlertCache => { view_id => $view->id, user_id => undef });

        # Cleanup any user_id alerts for users that no longer have this alert
        if ($options{all_users})
        {
            $::db->delete(AlertCache => {
                view_id => $view->id,
                user_id => [ -and => [ map +{ '!=' => $_->id }, @users ] ],
            })->delete;
        }
    }
    else
    {   # Cleanup specific user_id alerts for (now) non-curuser alert
        $::db->delete(AlertCache => {
            view_id => $view->id,
            user_id => { '!=' => undef },
        });
    }

    $guard->commit;
}

1;

