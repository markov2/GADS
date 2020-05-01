package Linkspace::User::Person;

use warnings;
use strict;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::DB::Table', 'Linkspace::User';

use Log::Report 'linkspace';
use Scalar::Util qw(blessed);
use JSON         'decode_json';

sub db_table { 'User' }

sub db_field_rename { +{
    account_request  => 'is_account_request',
    lastview         => 'last_view_id',
    organisation     => 'organisation_id',
    session_settings => 'session_settings_json',
    title            => 'title_id',
} };

__PACKAGE__->db_accessors;

#XXX lastview never set?  unused?

### 2020-04-18: columns in GADS::Schema::Result::User
# id                    department_id         limit_to_view
# site_id               email                 organisation
# title                 failcount             password
# value                 firstname             pwchanged
# account_request       freetext1             resetpw
# account_request_notes freetext2             session_settings
# aup_accepted          lastfail              stylesheet
# created               lastlogin             surname
# debug_login           lastrecord            team_id
# deleted               lastview              username


=head1 NAME
Linkspace::User::Person - someone via the web interface

=head1 SYNOPSIS

=head1 DESCRIPTION
These are the users which get a login via the web interface.  The existence
of these users is managed by L<Linkspace::Users>.

=head1 METHODS: Constructors
=cut

sub user_validate($)
{   my ($thing, $insert) = @_;
    $thing->Linkspace::User::user_validate($insert);

    length($insert->{firstname} //'') <= 128
        or error __"Forename must have less than 128 characters";
        
    length($insert->{surname}   //'') <= 128
        or error __"Surname must have less than 128 characters";

    $::session->site->validate_workspot($insert);
    $thing;
}

sub user_create($%)
{   my ($class, $insert, %args) = @_;

    $insert->{username}  = $insert->{email};
    $insert->{value}   ||= ($insert->{surname} //'').', '.($insert->{firstname} //'');
    $insert->{created} ||= DateTime->now,
    $insert->{resetpw} ||= Session::Token->new(length => 32)->get;
    $insert->{session_settings} ||= {};

    my @relations = (
        group_ids       => delete $insert->{group_ids},
        permissions     => delete $insert->{permissions},
        view_limits_ids => delete $insert->{view_limits_ids},
    );

    my $self = $class->create($insert, %args);
    $self->_update_relations(@relations);   
    $self;
}

sub user_update($)
{   my ($self, $update) = @_;

    if(exists $update->{firstname} || exists $update->{surname})
    {   my $f = exists $update->{firstname} ? $update->{firstname} : $self->firstname;
        my $s = exists $update->{surname}   ? $update->{surname}   : $self->surname;
        $update->{value} = ($s // '').', '.($f // '');
    }

    my @relations = (
        group_ids       => delete $update->{group_ids},
        permissions     => delete $update->{permissions},
        view_limits_ids => delete $update->{view_limits_ids},
    );

    $self->update($update);
    $self->_update_relations(@relations);   
    $self;
}

sub _update_relations(%)
{   my ($self, %args) = @_;

    $self->_set_group_ids($args{group_ids});

    if(my $perms = $args{permissions})
    {   $::session->user->is_admin
            or error __"You do not have permission to set global user permissions";

        # Permissions are still names here.
        $self->_set_permissions(@$perms);
    }

    if(my $view_limits = $args{view_limits_ids})
    {   my @view_limits = grep /\S/,
           ref $view_limits eq 'ARRAY' ? @$view_limits : $view_limits;
        $self->_set_view_limits(\@view_limits);
    }
}

sub user_delete(%)
{   my $self = shift;
    $self->retire(@_);
    $self->_record->delete_related('audits');
    $self->delete;
    $self;
}

#---------------------
=head1 METHODS: Accessors

=head2 $person->retire(%options);
=cut

sub retire(%)
{   my ($self, %args) = @_;

    if($self->is_account_request)
    {   # Properly delete if account request - no record needed
        $self->delete;
        return;
    }

    $self->_update_relations(
        group_ids       => [],
        permissions     => [],
        view_limits_ids => [],
    );
    $self->_graphs_delete;
    $self->_alerts_delete;
    $self->_views_delete;
    $self->_record->delete_related('dashboards');
    $self->update({ last_view_id => undef, deleted => DateTime->now });
    $self;
}

sub path { my $self = shift; $self->site->path.'/'.$self->username }

sub session_settings { decode_json $_[0]->session_settings_json }

sub session_update($)
{   my ($self, $settings) = @_;
    $self->update({ session_settings_json => encode_json $settings} );
}


#-----------------------
=head1 METHODS: Groups

=head2 \@groups = $user->groups_viewable;
Groups that this user should be able to see for the purposes of things like
creating shared graphs.
=cut

has groups_viewable => (
    is      => 'lazy',
);

sub _build_groups_viewable
{   my $self = shift;

    return $::session->site->groups
        if $self->is_admin;

    # Layout admin, all groups in their layout(s)
    #XXX smart, but maybe use the abstraction
    my $sheet_ids_rs = $::db->search(InstanceGroup => {
        'me.permission'       => 'layout',
        'user_groups.user_id' => $self->id,
    },{
        join => { group => 'user_groups' },
    })->get_column('me.instance_id');

    my $owner_groups = $::db->search(LayoutGroup => {
        instance_id => { -in => $sheet_ids_rs->as_query },
    }, {
        join => 'layout',
    });

    my %groups = map +($_->group_id => $_->group),
        $owner_groups->all, $self->user_groups;

    [ values %groups ];
}

=head2 my $member_of = $user->in_group($which);
Returns true when the user is member of the groups which is specified as
group_id or object.
=cut

has _in_group => (
    is      => 'lazy',
    builder => sub { +{ map +($_->group_id => $_), $_[0]->_record->user_groups} },
);

sub in_group($)
{   my ($self, $which) = @_;
    my $group_id = blessed $which ? $which->id : $which;
    $self->_in_group->{$which};
}

=head2 \@group = $user->groups;
Returns group records.
=cut

sub groups { [ map $_->group, values %{$_[0]->_in_group} ] }

# $user->_set_group_ids(\@group_ids);
sub _set_group_ids
{   my ($self, $group_ids) = @_;
    defined $group_ids or return;

    my $in_group = $self->_in_group;
    my $is_admin = $self->is_admin;

    foreach my $g (@$group_ids)
    {   next if $is_admin || $in_group->{$g};
        $self->find_or_create_related(user_groups => { group_id => $g });
    }

    # Delete any groups that no longer exist
    my @has_group_ids = map $_->id,
        grep $is_admin || $in_group->{$_->id},
            @{$self->site->groups->all_groups};

    #XXX this is too complex
    my %search;
    $search{group_id} = { -not_in => @$group_ids } if @$group_ids;
    $self->_record->search_related(user_groups => \%search)
        ->search({ group_id => \@has_group_ids })
        ->delete;
}

#-----------------------
=head1 METHODS: Views

=head2 $user->view_limits_with_blank
Used to ensure an empty selector is available in the user edit page.
=cut

sub view_limits_with_blank
{   my $view_limits = shift->view_limits;
    $view_limits->count ? $view_limits : [ undef ];
}

# $user->_set_view_limits(\@view_ids);
# $user->_set_view_limits(\@views);

sub _set_view_limits
{   my ($self, $views) = @_;
    defined $views or return;
    my @view_ids = map +(blessed $_ ? $_->id : $_), @$views;

    $self->find_or_create_related(view_limits => { view_id => $_ })
        for @view_ids;

    # Delete any groups that no longer exist
    my %search;
    $search{view_id} = { -not_in => @view_ids }
        if @view_ids;

    $self->_record->search_related(view_limits => \%search)->delete;
}

sub _views_delete()
{   my $self = shift;
    $::db->delete(View => { user_id => $self->id });
}

#-----------------------
=head1 METHODS: Graphs
Manage the graphs which the user has selected.  It is global: although graphs
are per sheet, their numbers are unique.
=cut

### 2020-05-01: columns in GADS::Schema::Result::UserGraph
# id         user_id    graph_id

has _selected_graphs => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $selections = $::db->search(UserGraph => { user_id => $self->id });
        +{ map +($_ => 1), $selections->get_column('graph_id')->all };
    },
);

=head2 $user->set_graphs($sheet, \@graphs);
Both C<$sheet> and C<$graph> may be specified by object or id.
=cut

sub set_graphs
{   my ($self, $sheet, $graphs) = @_;
    my $sheet_id  = blessed $sheet ? $sheet->id : $sheet;
    my @graph_ids = map +(blessed $_ ? $_->id : $_), @$graphs;

    my $selected  = $self->_selected_graphs;
    my $user_id   = $self->id;

    $::db->create(UserGraph => { graph_id => $_, user_id => $user_id })
        for grep ! $selected->{$_}, @graph_ids;

    my %graph_ids = map +($_ => 1), @graph_ids;
    $::db->delete(UserGraph => { graph_id => $_, user_id => $user_id })
        for grep ! $graph_ids{$_}, keys %$selected;

    $self->_selected_graphs(\%graph_ids);
}

sub _graphs_delete()
{   my $self = shift;
    %{$self->_selected_graphs} = ();
    $::db->delete(UserGraph => { user_id => $self->id });
}

=head2 my $is_selected = $user->graph_is_selected($which);
Return true when the graph (specified as object or by id) is selected by the
user.
=cut

sub graph_is_selected($)
{   my ($self, $which) = @_;
    $self->_selected_graphs->{blessed $which ? $which->id : $which};
}

#-----------------------
=head1 METHODS: Permissions
The user's permissions are heavily cached, to make it perform.

=cut

# Inherited
sub is_admin { $_[0]->has_permission('superadmin') }


=head2 \%h = $user->sheet_permissions($sheet);
Returns a HASH which shows the user permissions which were set explicitly
for this sheet (layout instance).
=cut

has _sheet_perms => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;

        my $rs = $::db->search(InstanceGroup => {
            user_id => $self->id,
        },{
            select => [
                { max => 'instance_id' },
                { max => 'permission'  },
            ],
            as       => [ qw/instance_id permission/ ],
            group_by => [ qw/permission instance_id/ ],
            join     => { group => 'user_groups' },     #XXX why?
            result_class => 'HASH',
        });

        my %perms;
        $perms{$_->{instance_id}}{$_->{permission}} = 1
            for $rs->all;
        \%perms;
    },
);

sub sheet_permissions($) { $_[0]->_sheet_perms->{$_[1]->id} }

=head2 \%perm = $user->column_permissions($which);
Returns the permissions this user has for the columns.
=cut

has _col_perms => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        my $rs   = $::db->search(LayoutGroup => {
            user_id => $self->id,
        }, {
            select => [
                { max => 'layout.instance_id' },   #XXX Why?
                { max => 'me.layout_id' },
                { max => 'me.permission' },
            ],
            as       => [ qw/instance_id layout_id permission/ ],
            group_by => [ qw/me.permission me.layout_id/ ],
            join     => [
                'layout',
                { group => 'user_groups' },
            ],
            result_class => 'HASH',
        });

        my %perms;
        $perms{$_->{layout_id}}{$_->{permission}} = 1
            for $rs->all;
        \%perms;
    },
);

sub column_permissions($)
{   my ($self, $which) = @_;
    my $col_id = blessed $which ? $which->id : $which;
    $self->_col_perms->{$col_id} || {};
}

=head2 my $can = $user->can_access_column($column);
=cut

sub can_access_column($$)
{   my ($self, $column, $perm) = @_;
       $self->_col_perm->{$column->id}{$perm}
    || $self->_sheet_perms->{$column->sheet->id}{$perm};
}

=head2 my $has = $user->has_permission($perm);
Check whether the user has a permission (by name).
=cut

has _permissions => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        my %all = map +($_->id => $_->name), @{$self->all_permissions};
         +{ map +($all{$_->permission_id} => 1), $self->_record->user_permissions};
    },
);

sub has_permission($) { $_[0]->_permissions->{$_[1]} }

sub _set_permissions
{   my ($self, @permissions) = @_;

    my %want_perms = map +($_ => 1), @permissions;
    my %perm2id  = map +($_->name => $_->id), @{$self->all_permissions};

    #XXX why limited to these three?
    foreach my $perm (qw/useradmin audit superadmin/)
    {
        my $which = { permission_id => $perm2id{$perm} };
        if($want_perms{$perm})
        {   $self->_record->find_or_create_related(user_permissions => $which);
        }
        else
        {   $self->_record->search_related(user_permissions => $which)->delete;
        }
    }
}

#---------------------------
=head1: METHODS: Alerts
=cut

sub _alerts_delete()
{   my $self = shift;
    my $alerts = $self->_record->search_related(alerts => {});
    my @alert_ids = map $_->id, $alerts->all;
    $::db->delete(AlertSend => { alert_id => \@alert_ids });
    $alerts->delete;
}

#---------------------------
=head1: METHODS: other

=cut

sub export_hash
{   my $self = shift;
    #TODO Department, organisation etc not currently exported
    +{
        id              => $self->id,
        firstname       => $self->firstname,
        surname         => $self->surname,
        value           => $self->value,
        email           => $self->email,
        username        => $self->username,
        freetext1       => $self->freetext1,
        freetext2       => $self->freetext2,
        password        => $self->password,
        pwchanged       => $self->pwchanged && $self->pwchanged->datetime,
        deleted         => $self->deleted   && $self->deleted->datetime,
        lastlogin       => $self->lastlogin && $self->lastlogin->datetime,
        created         => $self->created   && $self->created->datetime,
        groups          => [ map $_->id, $self->groups ],
        permissions     => [ map $_->permission->name, $self->user_permissions ],
        account_request => $self->is_account_request,
        account_request_notes => $self->account_request_notes,
    };
}

=head2 my $has = $user->has_draft($sheet);
=cut

sub has_draft
{   my ($self, $sheet) = @_;
    my $sheet_id = blessed $sheet ? $sheet->id : $sheet;
    $::db->search(Current => {
        instance_id  => $sheet_id,
        draftuser_id => $self->id,
        'curvals.id' => undef,
    }, {
        join => 'curvals',
    })->next;
}

=head2 $user->password_reset;
=cut

sub password_reset()
{   my $self = shift;
    my $reset_code = Session::Token->new(length => 32)->get;
    $self->update({ resetpw => $reset_code, failcount => 0 });
    $self->resetpw($reset_code);
    $reset_code;
}

=head2 my $fail_count = $user->login_failed;
=cut

sub login_failed()
{   my $self = shift;
    my $newcount = $self->failcount + 1;
    $self->update({
        failcount => $newcount,
        lastfail  => DateTime->now,
    });
    $newcount;
}

=head2 my $text = $user->summary(%options);
Option C<field_separator> defaults to C<,>.
=cut

sub summary(%)
{   my ($self, %args) = @_;
    my $sep  = $args{field_separator} || ',';
    my $site = $::session->site;

    my @f = (
       [ 'first name' => $self->firstname ],
       [ surname      => $self->surname   ],
       [ email        => $self->email     ],
    );

    push @f, [ title => $self->title->name ] if $self->title;
    push @f, [ $site->register_freetext1_name => $self->freetext1 ] if $self->freetext1;
    push @f, [ $site->register_freetext2_name => $self->freetext2 ] if $self->freetext2;
    push @f, [ $site->register_organisation_name => $self->organisation->name ] if $self->organisation;
    push @f, [ $site->register_department_name => $self->department->name ] if $self->department;
    push @f, [ $site->register_team_name => $self->team->name ] if $self->team;

    #XXX it is easy to produce a nice table for this
    join $sep, map "$_->[0]: $_->[1]", @f;
}

#-----------------------
=head1 METHODS: Permissions

=head2 \@perms = $users->all_permissions;
=cut

has all_permissions => (
    is      => 'lazy',
    builder => sub { [ $::db->resultset('Permission')->all ] },
);

has _can_column => (
    is      => 'lazy',
    builder => sub
    {   my $self  = shift;
        my $perms = $::db->search(User => { 'me.id' => $self->id },
        {   prefetch => {
                user_groups => { group => { layout_groups => 'layout' } }
            },
            result_class => 'HASH',
        })->single;

#XXX needs more work: we already know the groups of the user, so may simply
#XXX get it from the groups.
        my %perms;
        foreach my $group (@{$perms->{user_groups}})
        {   $perms{$_->{layout_id}}{$_->{permission}} = 1
               for @{$group->{group}{layout_groups}};
        }
        \%perms;
    },
);

sub can_column($$)
{   my ($self, $column, $permission) = @_;
    $self->_can_column->{$column->id}{$permission};
}

#-----------------------
=head1 METHODS: Last used row
For each sheet, a read cursor is kept for the user: the place where we
are reading.

=head2 my $row_id = $user->row_cursor($sheet);
=cut

sub row_cursor($)
{   my ($self, $sheet) = @_;

    my $cursor = $::db->get_record(UserLastrecord => {
        'me.instance_id'  => $sheet->id,
        user_id           => $self->id,
        'current.deleted' => undef,
    }, { join => { record => 'current' } });

    $cursor ? $cursor->record_id : undef;
}

=head2 $user->set_row_cursor($sheet, $row);
Set the cursor for processing in C<$sheet> to the C<$row>, which can be a
object or id.
=cut

sub set_row_cursor($$)
{   my ($self, $sheet, $where) = @_;
    my $row_id = blessed $where ? $where->id : defined $where ? $where : return;

    my @unique = (user_id => $self->id, instance_id => $sheet->id);
    if(my $last = $::db->get_record(UserLastrecord => { @unique }))
         { $last->update({ record_id => $row_id }) }
    else { $::db->create(UserLastrecord => { @unique, record_id => $row_id }) }
}

=head2 $any_user->row_cursor_renumber($from, $to);
Change all references to the C<$from> row id into the C<$to> row id.
=cut

sub row_cursor_renumber($$)
{   my ($self, $from_row, $to_row) = @_;
    my $from_id = blessed $from_row ? $from_row->id : $from_row;
    my $to_id   = blessed $to_row   ? $to_row->id   : $to_row;
    $::db->update(UserLastrecord => { record_id => $from_id }, { record_id => $to_id });
}

1;
