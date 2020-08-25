package Linkspace::User::Person;

use warnings;
use strict;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::DB::Table', 'Linkspace::User';

use Log::Report 'linkspace';
use Scalar::Util qw/blessed weaken/;
use JSON         qw/decode_json/;

use Linkspace::Util qw/index_by_id to_id/;
use Linkspace::Row::Cursor ();

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

=head2 my $user = $class->from_name($name, %options);
Create the C<$user> which is selected based on a C<name>, which could
be the username or email address (usually both the same).
=cut

sub from_name($%)
{   my ($class, $name) = (shift, shift);
    my $record = $::db->get_record($class->db_table => { username => $name })
              || $::db->get_record($class->db_table => { email => $name });
    $record ? $class->new(@_, _record => $record) : undef;
}

sub _user_validate($)
{   my ($thing, $insert) = @_;
    $thing->Linkspace::User::_user_validate($insert);

    length($insert->{firstname} //'') <= 128
        or error __"Forename must have less than 128 characters";
        
    length($insert->{surname}   //'') <= 128
        or error __"Surname must have less than 128 characters";

    $::session->site->_validate_workspot($insert);
    $thing;
}

sub _user_create($%)
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

sub _user_update($)
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

    $self->update($update) if keys %$update;
    $self->_update_relations(@relations);   
    $self;
}

sub _update_relations(%)
{   my ($self, %args) = @_;

    $self->_set_group_ids($args{group_ids})
         ->_set_permissions($args{permissions});

    if(my $view_limits = $args{view_limits_ids})
    {   my @view_limits = grep /\S/,
           ref $view_limits eq 'ARRAY' ? @$view_limits : $view_limits;
        $self->_set_view_limits(\@view_limits);
    }
}

sub _user_delete(%)
{   my $self = shift;
    $self->retire(@_);
    $self->_record->delete_related('audits');
    $self->_record->delete_related('user_lastrecords');
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
#   $self->_dashboards_delete;
    $self->update({ last_view_id => undef, deleted => DateTime->now });
    $self;
}

sub path { my $self = shift; $self->site->path.'/'.$self->username }

sub session_settings { decode_json $_[0]->session_settings_json }

sub session_update($)
{   my ($self, $settings) = @_;
    $self->update({ session_settings_json => encode_json $settings} );
}

sub fullname { $_[0]->value }

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
    my $site = $self->site;

    return $site->groups
        if $self->is_admin;

    foreach my $sheet (@{$site->document->all_sheets})
    {   $sheet->user_can(layout => $self) or next;
    ...
    }

### 2020-05-02: columns in GADS::Schema::Result::InstanceGroup
# id          instance_id group_id    permission
#             Sheet       Group       layout

    # Layout admin, all groups in their layout(s)
    #XXX smart, but maybe use the abstraction
    my $sheet_ids_rs = $::db->search(InstanceGroup => {
        'me.permission'       => 'layout',
        'user_groups.user_id' => $self->id,
    },{
        join => { group => 'user_groups' },
    })->get_column('me.instance_id');

### 2020-05-02: columns in GADS::Schema::Result::LayoutGroup
# id         group_id   layout_id  permission
    my $owner_groups = $::db->search(LayoutGroup => {
        instance_id => { -in => $sheet_ids_rs->as_query },
    }, {
        join => 'layout',
    });

    my %groups = map +($_->group_id => $_->group),
        $owner_groups->all, $self->_record->user_groups;

    [ values %groups ];
}

=head2 my $member_of = $user->is_in_group($which);
Returns true when the user is member of the groups which is specified as
group_id or object.
=cut

has _in_group => (
    is        => 'lazy',
    predicate => 1,
    builder   => sub {
        my $self = shift;
        my $groups = $self->site->groups;
        my $gids   = $::db->search(UserGroup => { user_id => $self->id })->get_column('group_id');
        my $index  = index_by_id(map $groups->group($_), $gids->all);
        weaken $_ for values %$index;
        $index;
    },
);

sub is_in_group($)
{   my ($self, $which) = @_;
    my $group_id = blessed $which ? $which->id : $which;
    defined $group_id && exists $self->_in_group->{$group_id};
}

sub _add_group($)
{   my ($self, $group) = @_;
    my $index = $self->_in_group;
    $index->{$group->id} = $group;
    weaken $index->{$group->id};
    $self;
}

sub _remove_group($)
{   my ($self, $group) = @_;
    my $gid = $group->id;
    delete $self->_in_group->{$gid} if $self->_has_in_group;
    $::db->delete(UserGroup => {user_id => $self->id, group_id => $gid});
}

=head2 \@group = $user->groups;
Returns group records.
=cut

sub groups { [ sort {$a->name cmp $b->name} values %{$_[0]->_in_group} ] }

# $user->_set_group_ids(\@group_ids);
sub _set_group_ids
{   my ($self, $group_ids) = @_;
    defined $group_ids or return $self;

    my $in_group   = $self->_in_group;
    my %old_groups = map +($_ => $in_group->{$_}), keys %$in_group;
    my $groups     = $self->site->groups;

    foreach my $gid (@$group_ids)
    {   next if delete $old_groups{$gid};
        $groups->group_add_user($groups->group($gid), $self);
    }

    $groups->group_remove_user($_, $self) for values %old_groups;
    $self;
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
=head1 METHODS: Global permissions
In the user object experience, all permissions are handle by name only.  The
L<Linkspace::Site::Users> object manages the permission names.
=cut

### 2020-05-08: columns in GADS::Schema::Result::UserPermission
# id            user_id       permission_id

my %change_by_admin_only = map +($_ => 1), qw/useradmin audit superadmin/;
my %superadmin_rights    = map +($_ => 1), qw/layout view_create/;

has _permissions => (
    is        => 'lazy',
    predicate => 1,
    builder   => sub {
        my $self  = shift;
        my $perm_ids = $::db->search(UserPermission => { user_id => $self->id })
           ->get_column('permission_id');

        my $users = $self->site->users;
        +{ map +($users->_global_permid2name($_) => 1), $perm_ids->all };
    },
);

=head2 my $has = $user->has_permission($perm);
Check whether the user has a permission (by name).

=head2 my $is_admin = $user->is_admin;
Short for C<<$user->has_permission('superadmin')>>.

=head2 \@perms = $user->permissions;
Sorted permissions.
=cut

sub has_permission($)
{   my ($self, $perm) = @_;
    my $perms = $self->_permissions;
    $perms->{$perm} || ($superadmin_rights{$perm} && $perm->{superadmin});
}

sub is_admin { $_[0]->has_permission('superadmin') }
sub permissions { [ sort keys %{$_[0]->_permissions} ] }

=head2 my $perm_id = $user->add_permission($name);
=cut

sub add_permission($)
{   my ($self, $perm) = @_;
    ! $change_by_admin_only{$perm} || $::session->user->is_admin
        or error __"You do not have permission to set global user permissions";

    my $users   = $self->site->users;
    my $perm_id = $users->_global_perm2id($perm) or panic;

    if($self->_has_permissions)
    {   return $perm_id if $self->_permissions->{$perm};
        $self->_permissions->{$perm} = 1
    }

    $::db->create(UserPermission => {user_id => $self->id, permission_id => $perm_id});
    info __x"User {user.path} add permission '{perm}'", user => $self, perm => $perm;

    $users->component_changed;
    $perm_id;
}


=head2 my $perm_id = $user->remove_permission($name);
Remove a permission for this user.
=cut

sub remove_permission($)
{   my ($self, $perm) = @_;
    ! $change_by_admin_only{$perm} || $::session->user->is_admin
        or error __"You do not have permission to remove global user permissions";

    delete $self->_permissions->{$perm} or return
        if $self->_has_permissions;

    my $users   = $self->site->users;
    my $perm_id = $users->_global_perm2id($perm) or panic;

    $::db->delete(UserPermission => {user_id => $self->id, permission_id => $perm_id});
    info __x"User {user.path} remove permission '{perm}'", user => $self, perm => $perm;

    $users->component_changed;
    $perm_id;
}

# Access via user_create and user_update
sub _set_permissions
{   my ($self, $perms) = @_;
    $perms or return;

    my %old_perms = %{$self->_permissions};

    delete $old_perms{$_} || $self->add_permission($_)
        for @$perms;

    $self->remove_permission($_) for keys %old_perms;
    $self;
}

#-----------------------
=head1 METHODS: Sheet permissions
The user's permissions are heavily cached, to make it perform.


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

#-----------------------
=head1 METHODS: Column permissions
The user's permissions are heavily cached, to make it perform.

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
Option C<field_separator> defaults to C<, >.
=cut

sub summary(%)
{   my ($self, %args) = @_;
    my $sep  = $args{field_separator} || ', ';

    return join $sep, map "$_->[0]: $_->[1]",
       [ 'First name' => $self->firstname ],
       [ Surname      => $self->surname   ],
       [ Email        => $self->email     ],
       @{$self->site->workspot_summary($self)};
}

#XXX When collected via $site, speed can be improved with caching
sub department   { $_[0]->_record->department }
sub organisation { $_[0]->_record->organisation }
sub team         { $_[0]->_record->team }
sub title        { $_[0]->_record->title }

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
=head1 METHODS: Last used row per sheet
For each sheet, a read cursor is kept for the user: the place where we
are reading.

Currently, there is no caching implemented: does not seem useful.

=head2 my $cursor = $user->row_cursor($sheet);
Returns the row revision that the user was watching last.  It may have
disappeared, however.
=cut

sub row_cursor($)
{   my ($self, $sheet) = @_;
    Linkspace::Row::Cursor->for_user($self, $sheet);
}

=head2 my $cursor = $user->row_cursor_create($sheet, $revision);
=cut

sub row_cursor_create($$)
{   my ($self, $sheet, $revision) = @_;
    Linkspace::Row::Cursor->_cursor_create({ user => $self, sheet => $sheet });
}

=head2 my $cursor = $user->row_cursor_point($sheet, $revision);
Set the cursor for processing in C<$sheet> to the specified row C<$revision>, which
can be a object or id.
=cut

sub row_cursor_point($$)
{   my ($self, $sheet, $revision) = @_;
    if(my $cursor = $self->row_cursor($sheet))
    {   return $cursor->move($revision);
    }

    $self->row_cursor_create($sheet, $revision);
}

1;
