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
use Linkspace::Util    qw(email_valid iso2datetime);
use File::BOM          qw(open_bom);

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

use Linkspace::User;
use Linkspace::Group;
use Linkspace::Permission;

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

sub active_users($;$)
{   my ($self, $search, $attr) = @_;
    $::db->resultset('User')->active_users($search, $attr);
}

#-----------------
=head1 METHODS: Users

=head2 \@users = $users->all_users;
Returns all active users.
=cut

has all_users => (
    is      => 'lazy',
    builder => sub
    {   my $self = shift;
        my $all  = $self->active_users({}, {
            join     => { user_permissions => 'permission' },
            order_by => 'surname',
            collapse => 1
        });
        my $doc = $self->document;
        [ map Linkspace::User->from_record($_, document => $doc), $all->all ];
    },
);

=head2 \@emails = $users->useradmins_emails;
Returns a list of the email addresses of the people who maintain the site's
users.
=cut

has useradmins_emails => (
    is      => 'lazy',
    builder => sub
    {   my $user_admins = $_[0]->active_users( {
            'permission.name' => 'useradmin',
        }, {
            join     => { user_permissions => 'permission' },
            collapse => 1,
        });
        [ $user_admins->get_column('email')->all ];
    },
}

has account_requestors => (
    is      => 'lazy',
    builder => sub {
        my $requestors = $::db->search(User => { account_request => 1 })
        [ map $_[0]->user($_), $requestors->get_column('id')->all ];
    },
);

#XXX All following fields are located in the site table, but are used for
#XXX users.

sub titles()      { sort { $a->name cmp $b->name } $_[0]->site->titles }
sub teams()       { sort { $a->name cmp $b->name } $_[0]->site->teams }
sub organisations { sort { $a->name cmp $b->name } $_[0]->site->organisations }
sub departments   { sort { $a->name cmp $b->name } $_[0]->site->departments }

has user_fields => (
    is  => 'lazy',
    isa => ArrayRef,
);

sub _build_user_fields
{   my $self   = shift;
    my @fields = qw/Surname Forename Email/;

    my $site   = $self->site;
    push @fields, $site->organisation_name if $site->register_show_organisation;
    push @fields, $site->department_name   if $site->register_show_department;
    push @fields, $site->team_name         if $site->register_show_team;
    push @fields, 'Title'                  if $site->register_show_title;
    push @fields, $site->register_freetext1_name if $site->register_freetext1_name;
    push @fields, $site->register_freetext2_name if $site->register_freetext2_name;
    \@fields;
}

sub active_users
{   my ($self, $search) = (shift, shift);
    $search->{deleted}         = undef;
    $search->{account_request} = 0;
    $::db->search(User => $search, @_);
}

sub users_in_org
{   my ($self, $org_id) = @_;
    my $in_org = $self->active_users({ organisation => $org_id });
    [ map $self->user($_), $in_org->get_column('id')->all ];
}

=head2 my $user = $users->user($id);

=head2 my $user = $users->user(%which);
Returns a L<Linkspace::User> object.

   my $u = $users->user(4);
   my $u = $users->user(id => 4);  # same
   my $u = $users->user(email => $email);

=cut

sub user
{   my $self = shift;
    my $record = $::db->get_record(User => @_) or return;
    Linkspace::User->from_record($record, document => $self->document);
}

=head2 my $victim = $users->user_create(%insert);
Returns a newly created user, a L<Linkspace::User::Person> object.
=cut

sub _generic_user_validate($)
{   my ($self, $data) = @_;

    my $email = $data{email}
        or error __"An email address must be specified for the user";

    email_valid $email
        or error __"Invalid email address";

    length $data{firstname} <= 128
        or error __"Forename must be less than 128 characters";
        
    length $data{surname} <= 128
        or error __"Surname must be less than 128 characters";

    ! $data->{permissions} || $::session->user->is_admin
        or error __"You do not have permission to set global user permissions";
}

sub _user_value($)
{   my $data      = shift or return;
    my $firstname = $data->{firstname} || '';
    my $surname   = $data->{surname}   || '';
    "$surname, $firstname";
}

sub user_create
{   my ($self, %insert) = @_;
    $self->_generic_user_validate(\%insert);

    my $group_ids   = delete $insert{group_ids}
    my $perms       = delete $insert{permissions};
    my $view_limits_ids = delete $insert{view_limits_ids};

    my $email = $insert{username} = $insert{email};
    $insert{value}   ||= _user_value \%insert;
    $insert{created} ||= DateTime->now,
    $insert{resetpw} ||= Session::Token->new(length => 32)->get;

    error __x"User '{email}' already exists", email => $email
        if $self->search_active({email => $email})->count;

    my $site  = $self->site;

    $insert{organisation} || ! $site->register_organisation_mandatory
        or error __x"Please select a {name} for the user", name => $site->organisation_name;

    $insert{team_id} || ! $site->register_team_mandatory
        or error __x"Please select a {name} for the user", name => $site->team_name;

    $insert{department_id} || !$site->register_department_mandatory
        or error __x"Please select a {name} for the user", name => $site->department_name;

    my $guard = $::db->begin_work;

    # Delete account request user if this is a new account request   #XXX?
    $self->user_delete($insert{account_request});

    my $victim_id = $::db->create(User => \%insert)->id;
    my $victim  = $self->user($victim_id);

    $victim->update_relations(
        group_ids       => $group_ids,
        permissions     => $perms,
        view_limits_ids => $view_limits_ids,
    );

    my $msg     = __x"User created: id={id}, username={username}",
        id => $victim_id, username => $victim->username;

    $msg .= __x", groups: {groups}", groups => $group_ids if $group_ids;
    $msg .= __x", permissions: {permissions}", permissions => $perms if $perms;

    $::session->audit($msg, type => 'login_change');

    $guard->commit;

    $victim;
}

=head2 $users->user_update($which, %update);
=cut

sub user_update
{   my ($self, $which, %update) = @_;
    $self->_generic_user_validate(\%update);

    my $victim    = blessed $which ? $which : $::db->get_record(User => $which);
    my $victim_id = $victim->id;

    my @relations = (
        group_ids       => delete $insert{group_ids},
        permissions     => delete $insert{permissions},
        view_limits_ids => delete $insert{view_limits_ids},
    );

    my $guard    = $::db->begin_work;

    my $email    = $update{username} = $update{email};
    $update{value} ||= _user_value \%update;

    my $username = $update{username} ||= $email;
    my $old_name = $victim->username;

    if(lc $username ne lc $old_name)
    {   $self->search_active({ username => $username })->count
            and error __x"Email address {email} already exists as an active user", email => $email;

        $::session->audit("Username $old_name (id $victim_id) changed to $username",
            type => 'login_change');
    }

    $::db->update(User => $victim_id, \%update);
    $victim = $self->user($victim_id);       # reload upgraded user
    $victim->update_relations(@relations);

    my $msg = __x"User updated: id={id}, username={username}",
        id => $victim_id, username => $username;
    $::session->audit($msg, type => 'login_change');

    $guard->commit;
    $victim;
}

=head $users->user_delete($user_id);
=cut

sub user_delete($)
{   my ($self, $which) = @_;
    my $victim_id = blessed $which ? $which->id : $which;

    #XXX remove from groups?
    $::db->update(User => $victim_id, { deleted => \'NOW' });
}

=head2 my $csv = $users->cvs;
Create the byte contents for a CVS file.
=cut

sub csv
{   my $self = shift;
    my $csv  = Text::CSV::Encoded->new({ encoding  => undef });

    my $site = $self->site;
    # Column names
    my @columns = qw/ID Surname Forename Email Lastlogin Created/;
    push @columns, 'Title'                if $site->register_show_title;
    push @columns, 'Organisation'         if $site->register_show_organisation;
    push @columns, $site->department_name if $site->register_show_department;
    push @columns, $site->team_name       if $site->register_show_team;
    push @columns, $site->register_freetext1_name if $site->register_freetext1_name;
    push @columns, $site->register_freetext2_name if $site->register_freetext2_name;
    push @columns, 'Permissions', 'Groups', 'Page hits last month';

    $csv->combine(@columns)
        or error __x"An error occurred producing the CSV headings: {err}", err => $csv->error_input;
    my @csvout = $csv->string;

    # All the data values
    my @users = $self->active_users({}, {
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
    })->all;

    my %user_groups = map +($_->id => [ $_->user_groups ]),
        $self->active_users({}, { prefetch => { user_groups => 'group' }})->all;

    my %user_permissions = map +($_->id => [ $_->user_permissions ]),
        $self->active_users({}, { prefetch => { user_permissions => 'permission' }})->all;

    my @col_order = qw/surname_max firstname_max email_max lastlogin_max created_max/;
    push @col_order, 'title_max'        if $site->register_show_title;
    push @col_order, 'organisation_max' if $site->register_show_organisation;
    push @col_order, 'department_max'   if $site->register_show_department;
    push @col_order, 'team_max'         if $site->register_show_team;
    push @col_order, 'freetext1_max'    if $site->register_freetext1_name;
    push @col_order, 'freetext2_max'    if $site->register_freetext2_name;

    foreach my $victim (@users)
    {
        my $id  = $victim->get_column('id_max');
        my @row = map $victim->get_column($_), @col_order;
        push @row, join '; ', map $_->permission->description, @{$user_permissions{$id}};
        push @row, join '; ', map $_->group->name, @{$user_groups{$id}};
        push @row, $victim->get_column('audit_count');

        $csv->combine($id, @row)
            or error __x"An error occurred producing a line of CSV: {err}",
                err => "".$csv->error_diag;
        push @csvout .= $csv->string;
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
    my %user_fields = map +(lc $_ => 1) @{$self->user_fields};

    my (%in_col, @invalid)
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

    my $nr_user = 0;
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
        $nr_users++;

        push @welcome_emails, [ email => $email, code => $user->resetpw ];
    }

    if (@errors)
    {   # Report processing errors without sending mails.

        my @e = map (join ',', @{$_->[0]}) . " ($_->[1])", @errors;
        error __x"The upload failed with errors on the following lines: {errors}",
            errors => join '; ', @e;
    }

    $guard->commit;

    $::linkspace->mailer->send_welcome(@$_)
        for @welcome_emails;

    $nr_users;
}

=head2 \@h = $users->match($string);
Search users with contain the C<$string> in their name or username/email.  Returned
are simple hashes with the user id and some formatted name.
=cut

sub match
{   my ($self, $query) = @_;
    my $pattern = "%$query%";

    my $users = $self->search_active({ -or => [
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

=head2 my $gid = $class->group_create(%insert);
=cut

sub group_create(%)
{   my ($class, %insert) = @_;
    $insert{site_id} = $::session->site->id;
    $::db->create(Group => \%insert);
}

=head2 $users->group_delete($group);
=cut

sub group_delete($)
{   my ($self, $victim) = @_;

    my $group_ref = { group_id => $victim->id };
    $::db->delete($_ => $group_ref)
        for qw/LayoutGroup InstanceGroup UserGroup/;

    $victim->delete;
}

=head2 \@groups = $users->all_groups;
=cut

has all_groups => (
    is      => 'lazy',
    builder => sub
    {   my $groups = $::db->search(Group => {}, { order_by => 'me.name' });
        [ map Linkspace::Group->from_record($_), $groups_rs->all ];
    },
);

=head2 my $group = $site->group($which);
Returns a L<Linkspace::Group>.  Use C<id> or a C<name>.
=cut

has _group_index => (
    is      => 'lazy',
    builder => sub { +{ map +($_->id => $_, $_->name), $_[0]->all_groups } },
}

sub group($) { $_[0]->_group_index->{$_[1]} }

#---------------------
=head1 METHODS: Permissions
=cut

has all_permissions => (
    is      => 'lazy',
    builder => sub { [ $::db->search(Permission => {}, { order_by => 'order' })->all ] },
);

sub permission_shorts { Linkspace::Permission->all_short }

#---------------------
=head1 METHODS: Other

=cut

sub sheet_unuse($)
{    my ($self, $sheet) = @_;
     $::db->delete(InstanceGroup => { instance_id => $sheet->id });
}

sub site_unuse($)
{   my ($self, $site) = @_;
    $::db->delete(Users  => { instance_id => $site->id });
    $::db->delete(Groups => { instance_id => $site->id });
}

1;

