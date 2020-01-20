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

package GADS::Users;

use Log::Report 'linkspace';

use DateTime           ();
use Session::Token     ();
use Text::CSV          ();
use Text::CSV::Encoded ();
use Linkspace::Util    qw(email_valid iso2datetime);
use File::BOM          qw(open_bom);

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

has site => (
    is       => 'ro',
    required => 1,
    weakref  => 1,
);

has all => (
    is  => 'lazy',
    isa => ArrayRef,
);

sub _build_all
{   [ shift->active_users({}, {
        join     => { user_permissions => 'permission' },
        order_by => 'surname',
        collapse => 1,
    })->all ];
}

has all_admins => (
    is  => 'lazy',
    isa => ArrayRef,
);

sub _build_all_admins
{   my $self  = shift;
    [ $self->active_users( {
        'permission.name' => 'useradmin',
    }, {
        join     => { user_permissions => 'permission' },
        order_by => 'surname',
        collapse => 1,
    })->all ];
}

has permissions => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub { [ $::db->search(Permission => {}, { order_by => 'order' })->all ] },
);

has register_requests => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub { [ $::db->search(User => { account_request => 1 })->all ] },
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
    $search->{deleted} = undef;
    $search->{account_request} = 0;
    $::db->search(User => $search, @_);
}

sub all_in_org
{   my ($self, $org_id) = @_;
    [ $self->active_users({ organisation => $org_id })->all ];
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
    Linkspace::User->from_record($record);
}

=head2 my $code = $users->user_password_reset($email);
=cut

sub user_password_reset($)
{   my ($self, $email) = @_;
    my $user = $self->user(email => $email) or return;

    my $reset_code = Session::Token->new(length => 32)->get
    $self->user_update($user->id, { resetpw => $reset_code });

    $reset_code;
}

sub user_create
{   my ($self, %insert) = @_;

    my $email = $insert{email}
        or error __"An email address must be specified for the user";

    email_valid $email
        or error __"Please enter a valid email address for the new user";

    error __x"User {email} already exists", email => $email
        if $self->search_active({email => $email})->count;

    my $site  = $self->site;

    error __x"Please select a {name} for the user", name => $site->organisation_name
        if !$insert{organisation} && $site->register_organisation_mandatory;

    error __x"Please select a {name} for the user", name => $site->team_name
        if !$insert{team_id} && $site->register_team_mandatory;

    error __x"Please select a {name} for the user", name => $site->department_name
        if !$insert{department_id} && $site->register_department_mandatory;

    my $guard = $::db->begin_work;

    # Delete account request user if this is a new account request
    #XXX?
    if (my $uid = $insert{account_request})
    {   $::db->delete(User => $uid);
    }

    myy $code = $insert{resetpw} ||= Session::Token->new(length => 32)->get;
    $insert{created} ||= DateTime->now,
    $insert{value}   ||= ($insert{firstname} || '') . ', ' . ($insert{surname} || '');

    my $user_rs = $::db->create(User => \%insert);
    my $user_id = $user_rs->id;

    $::session->audit->login_change(
        __x"User created: id={id}, username={username}",
            id => $user_id, username => $insert{username}
    );

    $guard->commit;

    ($user_rs, $code);
}

sub user_update($$)
{   my ($self, $which, $what) = @_;
    #XXX check when username/email changes to not collide with existing user?
    $::db->update(User => $which, $what);
}

sub register
{   my ($self, $params) = @_;

    my $email = $params->{email};
    email_valid $email
        or error __"Please enter a valid email address";

    my %new   = (
        firstname => ucfirst $params->{firstname},
        surname   => ucfirst $params->{surname},
        username  => $email,
        email     => $email,
        account_request       => 1,
        account_request_notes => $params->{account_request_notes},
    );

    my $site = $self->site;
    my @fields;
    push @fields, 'organisation' if $site->register_show_organisation;
    push @fields, 'department_id'if $site->register_show_department;
    push @fields, 'team_id'      if $site->register_show_team;
    push @fields, 'title'        if $site->register_show_title;
    push @fields, 'freetext1'    if $site->register_freetext1_name;
    push @fields, 'freetext2'    if $site->register_freetext2_name;

    defined $params->{$_} && ($new{$_} = $params->{$_})
        for @fields;

    my $user_rs = $::db->create(User => \%new);
    my $user    = $::linkspace->users->user($user_rs->id);

    # Email admins with account request
    my @f = (
        "First name: $new{firstname}",
        "surname: $new{surname}",
        "email: $new{email}",
    );

    push @f, "title: ".$user->title->name if $user->title;
    push @f, $site->register_freetext1_name.": $new{freetext1}" if $new{freetext1};
    push @f, $site->register_freetext2_name.": $new{freetext2}" if $new{freetext2};
    push @f, $site->register_organisation_name.": ".$user->organisation->name if $user->organisation;
    push @f, $site->register_department_name.": ".$user->department->name if $user->department;
    push @f, $site->register_team_name.": ".$user->team->name   if $user->team;

    my $f    = join ',', @f;
    my $text = <<__EMAIL;
A new account request has been received from the following person:

$f

User notes: $new{account_request_notes}
__EMAIL

    $::linkspace->mailer->send({
        emails  => [ map $_->email, $self->all_admins ],
        subject => 'New account request',
        text    => $text,
    });
}

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
    my $csvout = $csv->string."\n";

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

    my %user_groups = map { $_->id => [ $_->user_groups ] }
        $self->active_users({}, { prefetch => { user_groups => 'group' }})->all;

    my %user_permissions = map { $_->id => [ $_->user_permissions ] }
        $self->active_users({}, { prefetch => { user_permissions => 'permission' }})->all;

    foreach my $user (@users)
    {
        my $id = $user->get_column('id_max');
        my @csv = (
            $id,
            $user->get_column('surname_max'),
            $user->get_column('firstname_max'),
            $user->get_column('email_max'),
            $user->get_column('lastlogin_max'),
            $user->get_column('created_max'),
        );
        push @csv, $user->get_column('title_max')      if $site->register_show_title;
        push @csv, $user->get_column('organisation_max') if $site->register_show_organisation;
        push @csv, $user->get_column('department_max') if $site->register_show_department;
        push @csv, $user->get_column('team_max')       if $site->register_show_team;
        push @csv, $user->get_column('freetext1_max')  if $site->register_freetext1_name;
        push @csv, $user->get_column('freetext2_max')  if $site->register_freetext2_name;
        push @csv, join '; ', map $_->permission->description, @{$user_permissions{$id}};
        push @csv, join '; ', map $_->group->name, @{$user_groups{$id}};
        push @csv, $user->get_column('audit_count');

        $csv->combine(@csv)
            or error __x"An error occurred producing a line of CSV: {err}",
                err => "".$csv->error_diag;
        $csvout .= $csv->string."\n";
    }
    $csvout;
}


sub upload
{   my ($self, $file, %options) = @_;

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

        my %values = (
            firstname     => $cell->('forename') || '',
            surname       => $cell->('surname')  || '',
            email         => $cell->('email')    || '',
            username      => $cell->('email')    || '',
            freetext1     => $cell->($freetext1) || '',
            freetext2     => $cell->($freetext2) || '',
            title         => $cell->('title')    || '',
            organisation  => $org_id,
            department_id => $dep_id,
            team_id       => $team_id,
            view_limits   => $options{view_limits},
            groups        => $options{groups},
            permissions   => $options{permissions},
        );

        my ($user_rs, $code) = $self->user_create(%values);
        $values{code}  = $code;
        $nr_users++;

        push @welcome_emails, \%values;
    }

    if (@errors)
    {   # Report processing errors without sending mails.

        my @e = map { (join ',', @{$_->[0]}) . " ($_->[1])" } @errors;
        error __x"The upload failed with errors on the following lines: {errors}",
            errors => join '; ', @e;
    }

    # Won't get this far if we have any errors in the previous statement
    $guard->commit;

    $::linkspace->mailer->send_welcome($_)
        for @welcome_emails;

    $nr_users;
}

sub match
{   my ($self, $query) = @_;
    my $pattern = "%$query%";

    my $users = $self->search_active({ -or => [
        firstname => { -like => $pattern },
        surname   => { -like => $pattern },
        email     => { -like => $pattern },
        username  => { -like => $pattern },
    ]},{
        columns => [qw/id firstname surname username/],
    });

    map +{
        id   => $_->id,
        name => $_->surname.", ".$_->firstname." (".$_->username.")",
    }, $users->all;
}

1;

