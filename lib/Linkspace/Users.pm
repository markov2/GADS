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

use GADS::Email;
use Linkspace::Util    qw(email_valid);
use Text::CSV::Encoded;

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

has site => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);

has config => (
    is       => 'ro',
);

has all => (
    is  => 'lazy',
    isa => ArrayRef,
);

sub _build_all
{   [ shift->search_active({}, {
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
    [ $self->site->search(User => {
        deleted           => undef,
        account_request   => 0,
        'permission.name' => 'useradmin',
    }, {
        join     => { user_permissions => 'permission' },
        order_by => 'surname',
        collapse => 1,
    })->all ];
}

has titles => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub { [ shift->site->search(Title => {}, {order_by => 'name'})->all ] },
);

has organisations => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub { [ shift->site->search(Organisation => {}, {order_by => 'name'})->all ] },
);

has departments => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub { [ shift->site->search(Department => {}, { order_by => 'name'})->all ] },
);

has teams => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub { [ shift->site->search(Team => {}, { order_by => 'name'})->all ] },
);

has permissions => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub { [ shift->site->search(Permission => {}, { order_by => 'order' })->all ] },
);

has register_requests => (
    is      => 'lazy',
    isa     => ArrayRef,
    builder => sub { [ shift->site->search(User => { account_request => 1 })->all ] },
);

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

sub search_active
{   my ($self, $search) = (shift, shift);
    $search->{deleted} = undef;
    $search->{account_request} = 0;
    $self->site->search(User => $search, @_);
}

sub user_exists
{   my ($self, $email) = @_;
    $self->search_active({ email => $email })->count;
}

sub all_in_org
{   my ($self, $org_id) = @_;
    [ $self->site->search(User => {
        deleted         => undef,
        account_request => 0,
        organisation    => $org_id,
    })->all ];
}

sub register
{   my ($self, $params) = @_;

    my $site = $self->site;

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

    my @fields;
    push @fields, 'organisation' if $site->register_show_organisation;
    push @fields, 'department_id'if $site->register_show_department;
    push @fields, 'team_id'      if $site->register_show_team;
    push @fields, 'title'        if $site->register_show_title;
    push @fields, 'freetext1'    if $site->register_freetext1_name;
    push @fields, 'freetext2'    if $site->register_freetext2_name;

    defined $params->{$_} && ($new{$_} = $params->{$_})
        for @fields;

    my $user = $site->create(User => \%new);

    # Ensure that relations such as department() are resolved   XXX??
    $user->discard_changes;

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

    my $config = $self->config
        or panic "Config needs to be defined";

    GADS::Email->instance->send({
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
    my @users = $self->search_active({}, {
        select => [
            {
                max => 'me.id',
                -as => 'id_max',
            },
            {
                max => 'surname',
                -as => 'surname_max',
            },
            {
                max => 'firstname',
                -as => 'firstname_max',
            },
            {
                max => 'email',
                -as => 'email_max',
            },
            {
                max => 'lastlogin',
                -as => 'lastlogin_max',
            },
            {
                max => 'created',
                -as => 'created_max',
            },
            {
                max => 'title.name',
                -as => 'title_max',
            },
            {
                max => 'organisation.name',
                -as => 'organisation_max',
            },
            {
                max => 'department.name',
                -as => 'department_max',
            },
            {
                max => 'team.name',
                -as => 'team_max',
            },
            {
                max => 'freetext1',
                -as => 'freetext1_max',
            },
            {
                max => 'freetext2',
                -as => 'freetext2_max',
            },
            {
                count => 'audits_last_month.id',
                -as   => 'audit_count',
            }
        ],
        join     => [
            'audits_last_month', 'organisation', 'department', 'team', 'title',
        ],
        order_by => 'surname_max',
        group_by => 'me.id',
    })->all;

    my %user_groups = map { $_->id => [ $_->user_groups ] }
        $self->search_active({}, { prefetch => { user_groups => 'group' }})->all;

    my %user_permissions = map { $_->id => [ $_->user_permissions ] }
        $self->search_active({}, { prefetch => { user_permissions => 'permission' }})->all;

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

=head2 my $user = $users->get_user(%which);
Returns a L<Linkspace::User> object.

   my $u = $site->users->get_user(id => 4);
   my $u = $site->users->get_user(email => $email);

=cut

sub get_user
{   my ($self, %which) = @_;
    my $data = $self->site->find(\%which) or return ();

    Linkspace::User->from_record($data);
}

1;

