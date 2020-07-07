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

package Linkspace::Site::Users;

use Log::Report 'linkspace';

use DateTime           ();
use Session::Token     ();
use Text::CSV          ();
use Text::CSV::Encoded ();
use File::BOM          qw(open_bom);
use List::Util         qw(first);
use Scalar::Util       qw(blessed);

use Linkspace::Util    qw(is_valid_email is_valid_id iso2datetime index_by_id);
use Linkspace::User::Person ();
use Linkspace::Group        ();
use Linkspace::Permission   ();

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

use namespace::clean;

=head1 NAME

Linkspace::Site::Users - Manage Users, Groups and their Permissions

=head1 DESCRIPTION
Each Site has one set of Users, Groups and Permissions.  Together, they
implement tracibility and access restrictions.

=head1 METHODS: Constructors

=cut

has site => (
    is       => 'ro',
    required => 1,
    weakref  => 1,
);

sub component_changed() { $_[0]->site->changed('users') }

#-----------------
=head1 METHODS: Users
Maintain users which use the website.  The session user may also be a system
user, which is not stored in the database: it gets derived from operating
system information.

When the program only requests single users, it will only load those.
However, once it need to search them, they are all loaded at once (without
redoing the ones already resurrected before).

=head2 \@users = $users->all_users;
Returns all active users.
=cut

# The index contains all User::Person objects which have been resurrected.
has _users_index    => ( is => 'ro', default => sub { +{} } );
has _users_complete => ( is => 'rw', default => sub { 0 } );

sub _user_index_full
{   my $self  = shift;
    my $index = $self->_users_index;
    unless($self->_users_complete)
    {   $index->{$_->id} ||= $_ for    # ignore objects we already have
            Linkspace::User::Person->search_objects({
                deleted => undef,
                site    => $self->site,
            });
        $self->_users_complete(1);
    }
    $index;
}
    
sub all_users()
{   my $self = shift;
    [ sort { $a->value cmp $b->value }
        grep ! $_->is_account_request,
            values %{$self->_user_index_full} ];
}

=head2 \@emails = $users->useradmins_emails;
Returns a list of the email addresses of the people who maintain the site's
users.
=cut

sub useradmins_emails
{   my $self = shift;
    [ map $_->email, grep $_->has_permission('useradmin'), @{$self->all_users} ];
}

=head2 \@users = $users->account_requestors;
Return Users which are in the process of being added to the system.
=cut

sub account_requestors()
{   my $index = shift->_users_index_full;
    [ grep $_->is_account_request, values %$index ];
}

sub _active_users
{   my ($self, $search) = (shift, shift);
    $search->{deleted}     = undef;  # no delete time
    $search->{account_request} = 0;  # not in registration process
    $::db->search(User => $search, @_);
}

=head2 my $user = $users->user($which);
Returns a L<Linkspace::User> object.  When you do not pass an id, but a user
object, that will simply be returned.  When the id is C<undef>, an C<undef> is
returned silently.
=cut

sub user($)
{   my ($self, $user_id) = @_;
    return $user_id if ! defined $user_id || blessed $user_id;

    my $index = $self->_users_index;
    $index->{$user_id} ||= Linkspace::User::Person->from_id($user_id);
}

=head2 my $user = $users->user_by_name($email)
=head2 my $user = $users->user_by_name($username)
=cut

sub user_by_name()
{   my ($self, $name) = @_;
    my $index = $self->_users_index;
    my $found = first { $_->username eq $name || $_->email eq $name} values %$index;
    return $found if $found;  # 'accidentally' already loaded

    my $user = Linkspace::User::Person->from_name($name) or return;
    $index->{$user->id} = $user;
}

sub users_in_org
{   my ($self, $org_id) = @_;
    [ grep $_->organisation_id==$org_id, @{$self->all_users} ];
}

=head2 my $victim = $users->user_create(\%insert, %options);
Returns a newly created user, a L<Linkspace::User::Person> object.
=cut

sub user_create
{   my ($self, $values, %args) = @_;

    my $email = $values->{email}
        or error __"An email address must be specified for the user";

    error __x"User '{email}' already exists", email => $email
        if $self->user_by_name($email);

    my $victim = Linkspace::User::Person
        ->_user_validate($values)
        ->_user_create($values);

    $self->component_changed;
    $self->_users_index->{$victim->id} = $victim;
    $victim;
}

=head2 $users->user_update($which, $update);
=cut

sub user_update
{   my ($self, $which, $update) = @_;

    my $victim   = blessed $which ? $which : $self->user($which);
    $victim->isa('Linkspace::User::Person') or panic 'Only update persons';
    $victim->_user_validate($update);

    if(my $new_email = $update->{email})
    {   my $old_email = $victim->email;
        if(lc $new_email ne lc $old_email)
        {   my $other = $self->user_by_email($new_email);
            !$other || $victim->id != $other->id
                or error __x"Email address {email} already exists as an active user",
                     email => $new_email;
        }
    }

    $self->component_changed;
    $victim->_user_update($update);
}

=head2 $users->user_delete($user_id);
The user record is really removed.  You may use C<<$user->retire>> to keep
the record alive.
=cut

sub user_delete($)
{   my ($self, $which) = @_;
    my $victim = $self->user($which) or return;
    delete $self->_users_index->{$victim->id};
    $self->component_changed;
    $victim->_user_delete;
}

=head2 \@names = $users->user_fields;
The names of optional columns in the CSV.
=cut

sub user_fields()
{   my $site = shift->site;
    [ qw/Surname Forename Email/, @{$site->workspot_field_titles} ],
}

=head2 my $csv = $users->cvs;
Create the byte contents for a CVS file.
=cut

sub csv
{   my $self = shift;
    my $csv  = Text::CSV::Encoded->new({ encoding  => undef });

    my $site = $self->site;

    my @column_names = (
        qw/ID Surname Forename Email Lastlogin Created/,
        @{$site->workspot_field_titles},
        qw/Permissions Groups/, 'Page hits last month'
    );

    $csv->combine(@column_names)
        or error __x"An error occurred producing the CSV headings: {err}", err => $csv->error_input;
    my @csvout = $csv->string;

    #XXX Do we really need all these tricks here?  Just walk over the users and
    #XXX get the facts is slower but fast enough... and maintainable.
    # All the data values
    my $users_rs    = $self->_active_users({}, {
        select => [
            { max => 'me.id',             -as => 'id_max' },
            { max => 'surname',           -as => 'surname_max' },
            { max => 'firstname',         -as => 'firstname_max' },
            { max => 'email',             -as => 'email_max' },
            { max => 'lastlogin',         -as => 'lastlogin_max' },
            { max => 'created',           -as => 'created_max' },
            { max => 'title.name',        -as => 'title_max' },
            { max => 'organisation.name', -as => 'organisation_max' },
            { max => 'department.name',   -as => 'department_max' },
            { max => 'team.name',         -as => 'team_max' },
            { max => 'freetext1',         -as => 'freetext1_max' },
            { max => 'freetext2',         -as => 'freetext2_max' },
            { count => 'audits_last_month.id', -as => 'audit_count' }
        ],
        join     => [
            'audits_last_month', 'organisation', 'department', 'team', 'title',
        ],
        order_by => 'surname_max',
        group_by => 'me.id',
    });

    my %user_groups = map +($_->id => [ $_->user_groups ]),
        $self->_active_users({}, { prefetch => { user_groups => 'group' }})->all;

    my %user_permissions = map +($_->id => [ $_->user_permissions ]),
        $self->_active_users({},{ prefetch => { user_permissions => 'permission' }})->all;

    my @col_order, map "${_}_max",
        qw/surname firstname email lastlogin created/,
        @{$site->workspot_field_names};

    while(my $victim = $users_rs->next)
    {   my $id  = $victim->get_column('id_max');
        my @row = map $victim->get_column($_), @col_order;
        push @row, join '; ', map $_->permission->description, @{$user_permissions{$id}};
        push @row, join '; ', map $_->group->name, @{$user_groups{$id}};
        push @row, $victim->get_column('audit_count');

        $csv->combine($id, @row)
            or error __x"An error occurred producing a line of CSV: {err}",
                err => "".$csv->error_diag;
        push @csvout, $csv->string;
    }

    join "\n", @csvout, '';
}

sub upload
{   my ($self, $file, %args) = @_;

    my %generic_insert = (
        view_limits_ids => $args{view_limits},
        group_ids       => $args{groups},
        permissions     => $args{permissions},
    );

    $file or error __"Please select a file to upload";

    my $fh;
    # Use Open::BOM to deal with BOM files being imported
    # Can raise various exceptions which would cause panic
    try { open_bom($fh, $file) };
    error __"Unable to open CSV file for reading: ".$@->wasFatal->message if $@;

    my $csv = Text::CSV->new({ binary => 1 }) # should set binary attribute?
        or error "Cannot use CSV: ".Text::CSV->error_diag ();

    # Get first row for column headings
    my $row = $csv->getline($fh);

    # Valid headings
    my %user_fields = map +(lc $_ => 1), @{$self->user_fields};

    my (%in_col, @invalid);
    my $col_nr = 0;
    foreach my $cell (@$row)
    {
        if($user_fields{lc $cell})
        {   $in_col{lc $cell} = $col_nr;
        }
        else
        {   push @invalid, $cell;
        }
        $col_nr++;
    }

    my $cell = sub { my $nr = $in_col{$_[0]}; $nr ? $row->[$nr] : undef };

    ! @invalid
        or error __x"The following column headings were found invalid: {invalid}",
            invalid => \@invalid;

    defined $in_col{email}
        or error __"There must be an email column in the uploaded CSV";

    my $site = $self->site;
    my $freetext1 = lc $site->register_freetext1_name;
    my $freetext2 = lc $site->register_freetext2_name;
    my $org_name  = lc $site->register_organisation_name;
    my $dep_name  = lc $site->register_department_name;
    my $team_name = lc $site->register_team_name;

    # Map out titles and organisations for conversion to ID
    my %titles        = map { lc $_->name => $_->id } @{$site->titles};
    my %organisations = map { lc $_->name => $_->id } @{$site->organisations};
    my %departments   = map { lc $_->name => $_->id } @{$site->departments};
    my %teams         = map { lc $_->name => $_->id } @{$site->teams};

    my (@errors, @welcome_emails);

    my $guard = $::db->begin_work;

    while (my $row = $csv->getline($fh))
    {
        my $org_id;
        if(my $name = $cell->($org_name))
        {   $org_id  = $organisations{lc $name};
            $org_id or push @errors, [ $row, qq($org_name "$name" not found) ];
        }

        my $dep_id;
        if(my $name = $cell->($dep_name))
        {   $dep_id  = $departments{lc $name};
            $dep_id or push @errors, [ $row, qq($dep_name "$name" not found) ];
        }

        my $team_id;
        if(my $name = $cell->($team_name))
        {   $team_id = $teams{lc $name};
            $team_id or push @errors, [ $row, qq($team_name "$name" not found) ];
        }

        my $title_id;
        if(my $name  = $cell->('title'))
        {   $title_id = $titles{lc $name};
            $title_id or push @errors, [ $row, qq(Title "$name" not found) ];
        }

        my $email  = $cell->('email');
        my %insert = (
            firstname     => $cell->('forename') || '',
            surname       => $cell->('surname')  || '',
            email         => $cell->('email'),
            freetext1     => $cell->($freetext1) || '',
            freetext2     => $cell->($freetext2) || '',
            title         => $title_id,
            organisation  => $org_id,
            department_id => $dep_id,
            team_id       => $team_id,
            %generic_insert,
        );

        my $user      = $self->user_create(\%insert);
        push @welcome_emails, [ email => $email, code => $user->resetpw ];
    }

    if (@errors)
    {   # Report processing errors without sending mails.
        $guard->rollback;
        local $" = ',';
        my @e = map "@{$_->[0]} ($_->[1])", @errors;
        error __x"The upload failed with errors on the following lines: {errors}",
            errors => join '; ', @e;
    }

    $guard->commit;

    $::linkspace->mailer->send_welcome(@$_)
        for @welcome_emails;

    scalar @welcome_emails;
}

=head2 \@h = $users->match($string);
Search users with contain the C<$string> in their name or username/email.  Returned
are simple hashes with the user id and some formatted name.
=cut

sub match
{   my ($self, $query) = @_;
    my $pattern = "%$query%";  #XXX no quoting?

    #XXX in reality faster than search all_users()?
    my $users = $self->_search_active({
       -or => [
        firstname => { -like => $pattern },
        surname   => { -like => $pattern },
        email     => { -like => $pattern },
        username  => { -like => $pattern },
    ]},{
        columns   => [qw/id firstname surname username/],
    });

    map +{
        id   => $_->id,
        name => $_->surname.", ".$_->firstname." (".$_->username.")",
    }, $users->all;
}

#---------------------
=head1 METHODS: Manage groups

=head2 my $gid = $groups->group_create($insert);
There are (probably) only very few groups, so they all get instantiated.
=cut

has _group_index => (
    is        => 'lazy',
    predicate => 1,
    builder   => sub { index_by_id(Linkspace::Group
       ->search_objects({site => $_[0]->site})) },
);

sub group_create(%)
{   my ($self, $insert) = @_;
    my $group = Linkspace::Group->_group_create($insert);
    $self->_group_index->{$group->id} = $group;
    $self->component_changed;
    $group;
}

=head2 $groups->group_update($which, $update);
=cut

sub group_update($$)
{   my ($self, $which, $update) = @_;
    my $group = $self->group($which) or return;
    $group->_group_update($update);
    $self->component_changed;
    $group;
}

=head2 groupsusers->group_delete($which);
=cut

sub group_delete($)
{   my ($self, $which) = @_;
    my $group = $self->group($which) or return;
    delete $self->_group_index->{$group->id};
    $group->_group_delete;
    $self->component_changed;
    1;
}

=head2 \@groups = $groups->all_groups;
=cut

sub all_groups { [ sort { $a->name cmp $b->name } values %{$_[0]->_group_index} ] }

=head2 my $group = $groups->group($which);
Returns a L<Linkspace::Group>.  Use C<id> or a C<name>.  When a group object is
passed, it is simply returned unchanged.
=cut

sub group($)
{   my ($self, $which) = @_;
    return $which if blessed $which;

    my $index = $self->_group_index;
    is_valid_id $which ? $index->{$which}
    : first { $_->name eq $which } values %$index;
}

=head2 $groups->group_add_user($group, $user);
=cut

sub group_add_user($$)
{   my ($self, $group, $victim) = @_;
    my $user = $::session->user;   
    $user->is_admin || $user->is_in_group($group)
        or error __x"not allowed to add {user.username} to {group.path}",
              user => $victim, group => $group;

    $victim->_add_group($group);
    $group->_add_user($victim);
    info __x"user {user.username} added to {group.path}",
        user => $victim, group => $group;
    $self->component_changed;
    $self;
}

=head2 $groups->group_remove_user($group, $user);
=cut

sub group_remove_user($$)
{   my ($self, $group, $user) = @_;
    $user->_remove_group($group);   # includes recalculate permissions
    $group->_remove_user($user);
    info __x"user {user.username} removed from {group.path}",
        user => $user, group => $group;
    $self->component_changed;
    $self;
}

#---------------------
=head1 METHODS: Global user permissions
Manage the permissions which a user can have to perform administrative
actions. This is a very limited list, like 'superadmin'.
=cut

# These are static: will not change between reboots.
### 2020-05-08: columns in GADS::Schema::Result::Permission
# id  name  description  order

has _global_permissions => (
    is      => 'lazy',
    builder => sub { [ $::db->search(Permission => {}, { order_by => 'order' })->all ] },
);

has _global_perms_by_id => (
    is      => 'lazy',
    builder => sub
    {  my $perms = $_[0]->_global_permissions;
       +{ map +($_->id => $_->name), @$perms };
    },
);

has _global_perms_by_name => (
    is      => 'lazy',
    builder => sub
    {  my $perms = $_[0]->_global_permissions;
       +{ map +($_->name => $_->id), @$perms };
    },
);

### Access via $user->add_permission and ->remove_permisison
sub _global_perm2id { $_[0]->_global_perms_by_name->{$_[1]} }
sub _global_permid2name { $_[0]->_global_perms_by_id->{$_[1]} }

# Returns Permission table records, with id/name
sub global_permissions { $_[0]->_global_permissions }

#---------------------
=head1 METHODS: Access permissions
Access permissions, like 'read' and 'write' are organized per group.
=cut

sub permission_shorts { Linkspace::Permission->all_shorts }

#---------------------
=head1 METHODS: Other

=cut

sub sheet_unuse($)
{    my ($self, $sheet) = @_;
     $::db->delete(InstanceGroup => { instance_id => $sheet->id });
}

sub site_unuse($)
{   my ($self, $site) = @_;
    $self->user_delete($_)  for @{$self->all_users};
    $self->group_delete($_) for @{$self->all_groups};
}

sub view_unuse($)
{   my ($self, $which) = @_;
    my $view_id = blessed $which ? $which->id : defined $which ? $which : return;
    $_->update({ last_view_id => undef })
       for grep $_->last_view_id==$view_id, @{$self->all_users};

    $::db->delete(ViewLimit => {view_id => $view_id});
}

1;
