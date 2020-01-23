=pod
GADS - Globally Accessible Data Store
Copyright (C) 2015 Ctrl O Ltd

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

package GADS;

use CtrlO::Crypt::XkcdPassword;
use Crypt::URandom; # Make Dancer session generation cryptographically secure
use Data::Dumper;
use DateTime;
use File::Temp qw/ tempfile /;
use GADS::Alert;
use GADS::Column;
use GADS::Column::Autocur;
use GADS::Column::Calc;
use GADS::Column::Curval;
use GADS::Column::Date;
use GADS::Column::Daterange;
use GADS::Column::Enum;
use GADS::Column::File;
use GADS::Column::Intgr;
use GADS::Column::Person;
use GADS::Column::Rag;
use GADS::Column::String;
use GADS::Column::Tree;
use GADS::Config;
use GADS::Globe;
use GADS::Graph;
use GADS::Graph::Data;
use GADS::Graphs;
use GADS::Group;
use GADS::Import;
use Linkspace::Layout;
use GADS::MetricGroup;
use GADS::MetricGroups;
use GADS::Record;
use GADS::Records;
use GADS::RecordsGraph;
use GADS::Type::Permissions;
use GADS::View;
use GADS::Views;
use GADS::Helper::BreadCrumbs qw(Crumb);

use Linkspace::Audit  ();
use Linkspace::Util   qw(email_valid);

use HTML::Entities;
use HTML::FromText qw(text2html);
use JSON qw(decode_json encode_json);
use Math::Random::ISAAC::XS; # Make Dancer session generation cryptographically secure
use MIME::Base64;
use Session::Token;
use String::CamelCase qw(camelize);
use Text::CSV;
use Text::Wrap qw(wrap $huge);
$huge = 'overflow';
use URI::Escape qw/uri_escape_utf8/;
use WWW::Mechanize::PhantomJS;

use Dancer2; # Last to stop Moo generating conflicting namespace
use Dancer2::Plugin::DBIC;
use Dancer2::Plugin::Auth::Extensible;
use Dancer2::Plugin::Auth::Extensible::Provider::DBIC 0.623;
use Dancer2::Plugin::LogReport 'linkspace';

use GADS::API; # API routes

# set serializer => 'JSON';
set behind_proxy => config->{behind_proxy}; # XXX Why doesn't this work in config file

GADS::Config->instance(
    config       => config,
    app_location => app->location,
);

config->{plugins}->{'Auth::Extensible'}->{realms}->{dbic}->{user_as_object}
    or panic "Auth::Extensible DBIC provider needs to be configured with user_as_object";

my $password_generator = CtrlO::Crypt::XkcdPassword->new;

sub _update_csrf_token
{   session csrf_token => Session::Token->new(length => 32)->get;
}

my $site;

hook before => sub {

    # Some API calls will be AJAX from standard logged-in user
    #XXX can we specify any api_user without validation here?  Expect a token
    my $user = request->uri =~ m!^/api/! && var('api_user')
        ? var('api_user')
        : logged_in_user;

    return
        if request->dispatch_path =~ m{/invalidsite};

    $site = $::linkspace->site_for(request->base->host)
        or redirect '/invalidsite';

    $site->refresh;
    trace __x"Site ID is {id}", id => $site->id;

    $::session = Linkspace::Session::Dancer2->new(
        site => $site,
        user => $user,
    );

    if (request->is_post)
    {
        # Protect against CSRF attacks. NB: csrf_token can be in query params
        # or body params (different keys).
        my $token = query_parameters->get('csrf-token') || body_parameters->get('csrf_token');
        panic __x"csrf-token missing for uri {uri}, params {params}", uri => request->uri, params => Dumper({params})
            if !$token;
        error __x"The CSRF token is invalid or has expired. Please try reloading the page and making the request again."
            if $token ne session('csrf_token');

        # If it's a potential login, change the token
        _update_csrf_token()
            if request->path eq '/login';
    }

    if($user) {
        my $username = $user->username;
        my $method   = request->method;
        my $path     = request->path;
        my $query    = request->query_string;
        my $descr    = qq(User "$username" made "$method" request to "$path");
        $descr      .= qq( with query "$query") if $query;
        $::session->audit($descr, url => $path, method => $method);
    }

    # The following use logged_in_user so as not to apply for API requests
    if (logged_in_user)
    {
        if (config->{gads}->{aup})
        {
            # Redirect if AUP not signed
            my $aup_accepted;
            if (my $aup_date = $user->aup_accepted)
            {   my $aup_date_dt = $::db->parse_datetime($aup_date);
                $aup_accepted   = $aup_date_dt && DateTime->compare( $aup_date_dt, DateTime->now->subtract(months => 12) ) > 0;
            }
            redirect '/aup' unless $aup_accepted || request->uri =~ m!^/aup!;
        }

        if (config->{gads}->{user_status} && !session('status_accepted'))
        {
            # Redirect to user status page if required and not seen this session
            redirect '/user_status' unless request->uri =~ m!^/(user_status|aup)!;
        }
        elsif (logged_in_user_password_expired)
        {
            # Redirect to user details page if password expired
            forwardHome({ danger => "Your password has expired. Please use the Change password button
                below to set a new password." }, 'myaccount')
                    unless request->uri eq '/myaccount' || request->uri eq '/logout';
        }

        header "X-Frame-Options" => "DENY" # Prevent clickjacking
            unless request->uri eq '/aup_text' # Except AUP, which will be in an iframe
                || request->path eq '/file'; # Or iframe posts for file uploads (hidden iframe used for IE8)

        # Make sure we have suitable persistent hash to update. All these options are
        # used as hashrefs themselves, so prevent trying to access non-existent hash.
        my $persistent = session 'persistent';

        # Sheet can be addressed by id, short_name, long_name or even table$id
        my $sheet_ref
            = route_parameters->get('layout_name')
           || param('instance')
           || $persistent->{instance_id}
           || $::linkspace->setting(gads => 'default_instance');

        $sheet = $site->sheet($sheet_ref);

        if($sheet->id != ($persistent->{instance_id} || 0))
        {   session 'search' => undef;
            $persistent->{instance_id} = $sheet->id;
        }
    }
};

hook after => sub {
    $::session = $::linkspace->default_session;
}

hook before_template => sub {
    my $tokens = shift;

    my $base = $tokens->{base} || request->base;
    $tokens->{url} =
      { css  => "${base}css",
        js   => "${base}js",
        page => $base =~ s!.*/!!r, # Remove trailing slash   XXX no
      };
    $tokens->{scheme}  ||= request->scheme; # May already be set for phantomjs requests
    $tokens->{hostlocal} = config->{gads}->{hostlocal};
    $tokens->{header}    = config->{gads}->{header};

    # Possible for $layout to be undef if user has no access
    if($sheet &&
       ($sheet->user_can('approve_new') || $sheet->user_can('approve_existing')))
    {   $tokens->{user_can_approve} = 1;
        $tokens->{approve_waiting}  = $sheet->data->approval->count;
    }

    if (logged_in_user)
    {
        # var 'instances' not set for 404
        my $instances = var('instances') || GADS::Instances->new(user => $user);
        $tokens->{instances}     = $instances->all;
        $tokens->{user}          = $user;
        $tokens->{search}        = session 'search';
        # Somehow this sets the instance_id session if no persistent session exists
        $tokens->{instance_id}   = $sheet->id;
            if session 'persistent';

        if($sheet)
        {   $tokens->{instance_name}   = $sheet->name;
            $tokens->{user_can_edit}   = $sheet->user_can('write_existing');
            $tokens->{user_can_create} = $sheet->user_can('write_new');
            $tokens->{layout}    = $sheet->layout;   #XXX?
        }
        $tokens->{show_link} = rset('Current')->next ? 1 : 0; #XXX?
        $tokens->{v}         = current_view();  # View is reserved TT word
    }
    $tokens->{messages}      = session 'messages';
    $tokens->{site}          = $site;
    $tokens->{config}        = GADS::Config->instance;

    # This line used to be pre-request. However, occasionally errors have been
    # experienced with pages not submitting CSRF tokens. I think these may have
    # been race conditions where the session had been destroyed between the
    # pre-request and template rendering functions. Therefore, produce the
    # token here if needed
    _update_csrf_token()
        if !session 'csrf_token';
    $tokens->{csrf_token}    = session 'csrf_token';

    if($tokens->{page} =~ /(data|view)/)
    {   my $other = $site->user(session 'views_other_user_id');
        notice __x"You are currently viewing, editing and creating views as {name}",
            name => $other->value if $other;
    }
    session messages => [];
};

hook after_template_render => sub {
    _update_persistent();
};

sub _update_persistent
{
    if (my $user = logged_in_user)
    {
        $user->update({
            session_settings => encode_json(session('persistent')),
        });
    }
}

sub _forward_last_table
{
    forwardHome() if ! $site->remember_user_location;
    my $forward;
    if(my $l = session('persistent')->{instance_id})
    {   $forward = $site->sheet($l)->identifier;
    }
    forwardHome(undef, $forward);
}

get '/' => require_login sub {

    if (my $dashboard_id = query_parameters->get('did'))
    {   session('persistent')->{dashboard}->{0} = $dashboard_id;
    }

    my $dashboard_id = session('persistent')->{dashboard}->{0};

    my %params = (
        id     => $dashboard_id,
        user   => $user,
        site   => $site,
    );

    my $dashboard = $::db->resultset('Dashboard')->dashboard(%params);

    my $params = {
        readonly        => $dashboard->is_shared && !$user->is_admin,
        dashboard       => $dashboard,
        dashboards_json => $::db->resultset('Dashboard')->dashboards_json(%params),
        page            => 'index',
    };

    if (my $download = param('download'))
    {
        $params->{readonly} = 1;
        if ($download eq 'pdf')
        {
            my $pdf = _page_as_mech('index', $params, pdf => 1)->content_as_pdf;
            return send_file(
                \$pdf,
                content_type => 'application/pdf',
            );
        }
    }

    template 'index' => $params;
};

get '/ping' => sub {
    content_type 'text/plain';
    'alive';
};

any ['get', 'post'] => '/aup' => require_login sub {

    if (param 'accepted')
    {   update_current_user aup_accepted => DateTime->now;
        redirect '/';
    }

    template aup => {
        page => 'aup',
    };
};

get '/aup_text' => require_login sub {
    template 'aup_text', {}, { layout => undef };
};

# Shows last login time etc
any ['get', 'post'] => '/user_status' => require_login sub {

    if (param 'accepted')
    {   session status_accepted => 1;
        _forward_last_table();
    }

    template user_status => {
        lastlogin => logged_in_user_lastlogin,
        message   => config->{gads}->{user_status_message},
        page      => 'user_status',
    };
};

get '/login/denied' => sub {
    forwardHome({ danger => "You do not have permission to access this page" });
};

any ['get', 'post'] => '/login' => sub {

    my $login_change = sub { $::session->audit(@_, type => 'login_change') };
    my $user  = logged_in_user;

    # Don't allow login page to be displayed when logged-in, to prevent
    # user thinking they are logged out when they are not
    return forwardHome() if $user;

    my ($error, $error_modal);

    # Request a password reset
    if (param 'resetpwd')
    {
        if (my $username = param 'emailreset')
        {
            if(email_valid $username)
            {
                $login_change->("Password reset request for $username");
#XXX password_reset_send?  In plugin?
                my $result = password_reset_send(username => $username);

                defined $result
                    ? success(__('An email has been sent to your email address with a link to reset your password'))
                    : report({is_fatal => 0}, ERROR => 'Failed to send a password reset link. Did you enter a valid email address?');
                report INFO =>  __x"Password reset requested for non-existant username {username}", username => $username
                    if defined $result && !$result;
            }
            else
            {   $username =~ s/[^\w<>"'@.]/X/g;  # do not show controls
                $error = qq("$username" is not a valid email address);
                $error_modal = 'resetpw';
            }
        }
        else {
            $error = 'Please enter an email address for the password reset to be sent to';
            $error_modal = 'resetpw';
        }
    }

    my $users = $site->users;

    if (param 'register')
    {
        my $email = param 'email';
        error __"Self-service account requests are not enabled on this site"
            if $site->hide_account_request;

        # Check whether this user already has an account
        my $victim = $site->users->user(email => $email);

        if($victim)
        {
            if(process( sub {
                 my $resetpw = $user->password_reset;
                 $::linkspace->mailer->send_welcome(email => $email, code => $resetpw);
            }))
            {
                # Show same message as normal request
                return forwardHome(
                    { success => "Your account request has been received successfully" } );
            }
            $login_change->("Account request for $email. Account already existed, resending welcome email.");
            return forwardHome({ success =>
                "Your account request has been received successfully" });
        }

        my %insert = (
            firstname => ucfirst param('firstname'),
            surname   => ucfirst param('surname'),
            email     => $email,
            account_request       => 1,
            account_request_notes => param('account_request_notes'),
        );

        my @fields;
        push @fields, 'organisation'  if $site->register_show_organisation;
        push @fields, 'department_id' if $site->register_show_department;
        push @fields, 'team_id'       if $site->register_show_team;
        push @fields, 'title'         if $site->register_show_title;
        push @fields, 'freetext1'     if $site->register_freetext1_name;
        push @fields, 'freetext2'     if $site->register_freetext2_name;
        $insert{$_} = param $_ for @fields;

        my $victim = try { $users->user_create(\%insert) };
        if(my $exception = $@->wasFatal)
        {
            if ($exception->reason eq 'ERROR')
            {   $error = $exception->message->toString;
                $error_modal = 'register';
            }
            else
            {   $exception->throw;
            }
        }
        else
        {   $login_change->("New user account request for $email");
            my @to = map $_->email, $users->useradmins;
            $::linkspace->mailer->send_account_requested($victim, \@to);
            return forwardHome({ success =>
                "Your account request has been received successfully" });
        }
    }
    elsif(param('signin'))
    {
        my $username    = param 'username';
        my $remember_me = param 'remember_me';
        my $password    = param 'password';

        my $victim    = $site->users->user(username => $username);

        my $fail      = $victim->failcount >= 5
            && $victim->lastfail > DateTime->now->subtract(minutes => 15);

        $fail and assert "Reached fail limit for user $username";

        my ($success, $realm) = !$fail
            && authenticate_user($username, $password);

        if ($success) {
            # change session ID if we have a new enough D2 version with support
            app->change_session_id
                if app->can('change_session_id');

            session logged_in_user       => $username;
            session logged_in_user_realm => $realm;
            if($remember_me)
            {   my $secure = request->scheme eq 'https' ? 1 : 0;
                cookie remember_me => $username, expires => '60d',
                    secure => $secure, http_only => 1;
            }
            elsif(cookie 'remember_me')
            {   cookie remember_me => '', expires => '-1d'
            }
            $::session->user_login($victim);

            # Load previous settings and forward to previous table if applicable
            my $session_settings = try { decode_json $user->session_settings };
            session persistent => ($session_settings || {});
            _forward_last_table();
        }
        else
        {   $::session->audit("Login failure using username $username", type => 'login_failure');

            my $victim = $site->users->user(username => $username);
            if($victim && ! $victim->account_requested)
            {   my $fail_count = $victim->login_failed;
                trace "Fail count for $username is now $fail_count";
                report {to => 'syslog'},
                    INFO => __x"debug_login set - failed username \"{username}\", password: \"{password}\"",
                    username => $username, password => $password
                        if $user->debug_login;
            }
            report {is_fatal=>0}, ERROR => "The username or password was not recognised";
        }
    }

    template login => +{
        page          => 'login',
        error         => "".($error||""),
        error_modal   => $error_modal,
        username      => cookie('remember_me'),
        titles        => $users->titles,
        organisations => $users->organisations,
        departments   => $users->departments,
        teams         => $users->teams,
        register_text => $site->register_text,
    };
};

any ['get', 'post'] => '/edit/:id' => require_login sub {
    my $id = is_valid_id(param 'id');
    _process_edit($id) if $id;
};

any ['get', 'post'] => '/myaccount/?' => require_login sub {

    if (param 'newpassword')
    {
        my $new_password = _random_pw();
        if (user_password password => param('oldpassword'), new_password => $new_password)
        {
            $::session->audit('New password set for user', type => 'login change');

            # Don't log elsewhere
            return forwardHome({ success =>
                 qq(Your password has been changed to: $new_password)},
                 'myaccount', user_only => 1 );
        }

        return forwardHome({ danger =>
            "The existing password entered is incorrect"}, 'myaccount');
    }

    if (param 'submit')
    {   my $email  = param 'email';
        my %update = (
            firstname     => param('firstname'),
            surname       => param('surname'),
            email         => $email.
            freetext1     => param('freetext1'),
            freetext2     => param('freetext2'),
            title         => is_valid_id(param 'title'),
            organisation  => is_valid_id(param 'organisation'),
            department_id => is_valid_id(param 'department_id'),
            team_id       => is_valid_id(param 'team_id'),
        );

        if (process( sub { $site->users->user_update({email => $email}, \%update) }))
        {
            return forwardHome({ success =>
                "The account details have been updated" },
                'myaccount' );
        }
    }

    my $users = $site->users;
    template 'user' => {
        edit          => $user->id,
        users         => [ $user ],
        titles        => $users->titles,
        organisations => $users->organisations,
        departments   => $users->departments,
        teams         => $users->teams,
        page          => 'myaccount',
        breadcrumbs   => [ Crumb('/myaccount/' => 'my details') ],
    };
};

any ['get', 'post'] => '/system/?' => require_login sub {

    $user->is_admin
        or return forwardHome({ danger =>
            "You do not have permission to manage system settings"}, '');

    if (param 'update')
    {   my %update = (
            email_welcome_subject => param('email_welcome_subject'),
            email_welcome_text    => param('email_welcome_text'),
            name                  => param('name'),
        );

        if(process( sub { $site->site_update(%update) } )
        {   return forwardHome({ success =>
                 "Configuration settings have been updated successfully" } );
        }
    }

    template system => {
        page        => 'system',
        instance    => $site,
        breadcrumbs => [ Crumb('/system' => 'system-wide settings') ],
    };
};


any ['get', 'post'] => '/group/?:id?' => require_any_role [qw/useradmin superadmin/] => sub {
    my $group_id = is_valid_id(param 'id');

    my $doc = $site->document;
    my @permissions = GADS::Type::Permissions->all;

    if (param 'submit')
    {
        my %data = (name => param 'name');
        $data{$_} = param($_) ? 1 : 0
            for map $_->short, @permissions;

        my $action;
        if(process(sub {
            if($group_id)
            {   $doc->group_update($group_id => %data);
                $action = 'updated';
            }
            else
            {   $group_id = $doc->group_create(%data)->id;
                $action = 'created';
            }
        }))
        {
            return forwardHome({ success =>
                "Group has been $action successfully" }, 'group' );
        }
    }

    if (param 'delete')
    {
        if(process(sub { $doc->group_delete($group_id) }))
        {   return forwardHome({ success =>
                "The group has been deleted successfully" }, 'group' );
        }
    }

    my %params = (permissions => \@permissions);
    my @breadcrumbs = Crumb('/group' => 'groups');

    if(!defined $group_id)
    {   $params{page}   = 'group';
        $params{groups} = $site->all_groups;
    }
    elsif($group_id==0)    # id will be 0 for new group
    {   $params{page}   = 'group/0';
        push @breadcrumbs, Crumb('/group/0' => 'new group');
    }
    else
    {   $params{page}   = 'group';
        $params{group}  = my $group = $doc->group($group_id);
        push @breadcrumbs, Crumb("/group/$group_id" => $group->name);
    }

    $params{breadcrumbs} = \@breadcrumbs;

    template 'group' => \%params;
};

get '/table/?' => require_role superadmin => sub {

    template 'tables' => {
        page        => 'table',
        instances   => $site->document->all_sheets,
        breadcrumbs => [ Crumb('/table' => 'tables') ],
    };
};

any ['get', 'post'] => '/table/:id' => require_role superadmin => sub {

    my $sheet_id = is_valid_id(param 'id');
    if($sheet_id)
    {   $sheet = $site->sheet($sheet_id)
            or error __x"Sheet ID {id} not found", id => $sheet_id;
    }

    if(param 'submit')
    {   my %data = (
            name           => param 'name',
            name_short     => param 'name_short',
            sort_layout_id => param 'sort_layout_id',
            sort_type      => param 'sort_type',
            group_ids      => [ body_parameters->get_all('permissions') ],  ### perms?
        );

        my $msg;
        if(process(sub {
            if($sheet)
            {   $sheet->sheet_update($sheet, %data);
                $msg = 'The table has been updated successfully';
            }
            else
            {   $sheet = $site->documents->sheet_create(%data);
                $msg   = 'Your new table has been created successfully';
            }
        }))
        {
            # Switch user to new table
            return forwardHome({ success => $msg }, 'table' );
        }
    }
    elsif($sheet && param 'delete')
    {   if(process(sub { $sheet->sheet_delete }))
        {   return forwardHome({ success =>
                "The table has been deleted successfully" }, 'table' );
        }
    }

    my $table_name = $sheet_id ? $layout_edit->name : 'new table';
    my $table_id   = $sheet_id ? $layout_edit->instance_id : 0;

    template 'table' => {
        page        => $sheet_id ? 'table' : 'table/0',
        layout_edit => $sheet->layout,
        groups      => $site->groups,
        breadcrumbs => [
            Crumb('/table' => 'tables') =>
            Crumb("/table/$table_id" => $table_name),
        ],
    }
};

any ['get', 'post'] => '/user/upload' => require_any_role [qw/useradmin superadmin/] => sub {

    if (param 'submit')
    {
        my $count;
        my $file = upload('file') && upload('file')->tempname;
        if (process sub {
            $count = $site->users->upload($file,
                request_base => request->base,
                view_limits  => [ body_parameters->get_all('view_limits') ],
                groups       => [ body_parameters->get_all('groups') ],
                permissions  => [ body_parameters->get_all('permission') ],
                current_user => $user,
            )}
        )
        {
            return forwardHome(
                { success => "$count users were successfully uploaded" }, 'user' );
        }
    }

    my $users = $site->users;

    template 'user/upload' => {
        groups      => $site->groups,
        permissions => $users->permissions,
        user_fields => $users->user_fields,
        breadcrumbs => [
            Crumb('/user' => 'users'),
            Crumb('/user/upload' => "user upload"),
        ],
        # XXX Horrible hack - see single user edit route
        edituser    => +{ view_limits_with_blank => [ undef ] },
    };
};

any ['get', 'post'] => '/user/?:id?' => require_any_role [qw/useradmin superadmin/] => sub {

    my $id = body_parameters->get('id');
    my $users           = $site->users;
    my %all_permissions = map { $_->id => $_->name } @{$users->permissions};
    my $login_change    = sub { $::session->audit(@_, type => 'login_change') };

    my @show_users;

    if (param 'sendemail')
    {   my $org_id = param 'email_organisation';
        my @emails = map $_->email,
         ( $org_id ? @{$users->all_in_org($org_id)} : @{$users->all} );

        if(process( sub { $::linkspace->mailer->message(
            subject => param('email_subject'),
            text    => param('email_text'),
            emails  => \@emails,
        ) }))
        {
            return forwardHome(
                { success => "The message has been sent successfully" }, 'user' );
        }
    }

    # The submit button will still be triggered on a new org/title creation,
    # if the user has pressed enter, in which case ignore it
    if (param('submit') && !param('neworganisation') && !param('newdepartment') && !param('newtitle') && !param('newteam'))
    {
        my $account_request = param 'account_request';
        my %values = (
            firstname             => param('firstname'),
            surname               => param('surname'),
            email                 => param('email'),
            freetext1             => param('freetext1'),
            freetext2             => param('freetext2'),
            title                 => is_valid_id(param 'title'),
            organisation          => is_valid_id(param 'organisation'),
            department_id         => is_valid_id(param 'department_id'),
            team_id               => is_valid_id(param 'team_id'),
            account_request       => $account_request,
            account_request_notes => param('account_request_notes'),
            view_limits_ids       => [ body_parameters->get_all('view_limits') ],
            group_ids             => [ body_parameters->get_all('groups') ],
            permissions           => [ body_parameters->get_all('permission') ],
        );

        my $victim;
        if($id && ! $account_request)
        {   # Original username to update (hidden field)  XXX???
            if(process sub { $victim = $users->user_update($id => %values) })
            {
                return forwardHome(
                    { success => "User has been updated successfully" }, 'user' );
            }
        }
        elsif(process(sub { $victim = $users->user_create(%values) }))
        {   $::linkspace->mailer
                ->send_welcome(email => $victim->email, code => $victim->resetpw);

            return forwardHome(
                { success => "User has been created successfully" }, 'user' );
        }

        # In case of failure, pass back to form
        my @view_limits_with_blank = map +{ view_id => $_ },
            body_parameters->get_all('view_limits');

        $values{view_limits_with_blank} = \@view_limits_with_blank;
        push @show_users, \%values;
    }

    if (param('neworganisation') || param('newtitle') || param('newdepartment') || param('newteam'))
    {
        if(my $org = param 'neworganisation')
        {
            if (process( sub { $site->create(Organisation => {name => $org}) }))
            {
                $login_change->("Organisation $org created");
                success __"The organisation has been created successfully";
            }
        }

        if(my $dep = param 'newdepartment')
        {
            if (process( sub { $site->create(Department => { name => $dep }) }))
            {
                $login_change->("Department $dep created");
                my $depname = lc $site->register_department_name || 'department';
                success __x"The {dep} has been created successfully", dep => $depname;
            }
        }

        if(my $team = param 'newteam')
        {
            if (process( sub { $site->create(Team => { name => $team }) }))
            {
                $login_change->("Team $team created");
                my $teamname = lc $site->register_team_name || 'team';
                success __x"The {team} has been created successfully", team => $teamname;
            }
        }

        if(my $title = param 'newtitle')
        {
            if (process( sub { $site->create(Title => { name => $title }) }))
            {
                $login_change->("Title $title created");
                success __"The title has been created successfully";
            }
        }

        # Remember values of user creation in progress.
        # XXX This is a mess (repeated code from above). Need to get
        # DPAE to use a user object
        my $groups      = param('groups');
        my @groups      = ref $groups ? @$groups : ($groups || ());
        my %groups      = map +($_ => 1) @groups;
        my $view_limits_with_blank = [ map +{ view_id => $_ },
            body_parameters->get_all('view_limits') ];

        push @show_users, +{
            firstname              => param('firstname'),
            surname                => param('surname'),
            email                  => param('email'),
            freetext1              => param('freetext1'),
            freetext2              => param('freetext2'),
            title                  => { id => param('title') },
            organisation           => { id => param('organisation') },
            department_id          => { id => param('department_id') },
            team_id                => { id => param('team_id') },
            view_limits_with_blank => $view_limits_with_blank,
            groups                 => \%groups,
        };
    }

    if (my $delete_id = param('delete'))
    {
        return forwardHome(
            { danger => "Cannot delete current logged-in User" } )
            if logged_in_user->id eq $delete_id;

        my $victim = $::linkspace->users->user($delete_id);
        if(process( sub { $::$victim->retire } ))
        {   $login_change->("User ID $delete_id deleted");
            my $mailer = $::linkspace->mailer;

            if($self->account_request)
                 { $mailer->send_user_rejected($victim) }
            else { $mailer->send_user_deleted($victim)  }

            return forwardHome(
                { success => "User has been deleted successfully" }, 'user' );
        }
    }

    if (defined param 'download')
    {
        my $csv = $users->csv;
        my $header;
        if(my $head = $::linkspace->setting(gads => 'header'))
        {   $csv       = "$head\n$csv";
            $header    = "-$head";
        }
        # XXX Is this correct? We can't send native utf-8 without getting the error
        # "Strings with code points over 0xFF may not be mapped into in-memory file handles".
        # So, encode the string (e.g. "\x{100}"  becomes "\xc4\x80) and then send it,
        # telling the browser it's utf-8
        utf8::encode($csv);

        my $now = DateTime->now;
        return send_file( \$csv, content_type => 'text/csv; charset="utf-8"', filename => "$now$header.csv" );
    }

    my $register_requests;
    my $page        = 'user';
    my @breadcrumbs = Crumb('/user' => 'users');

    my $route_id = route_parameters->get('id');
    if($route_id)
    {   push @users, $users->user($route_id) if !@users;
        push @breadcrumbs, Crumb("/user/$route_id" => "edit user $route_id");
    }
    elsif(!defined $route_id)
    {   @users             = $users->all;
        $register_requests = $users->register_requests;
    }
    else # route_id==0
    {   # Horrible hack to get a limit view drop-down to display
        push @users, +{ view_limits_with_blank => [ undef ] } if !@users;
        push @breadcrumbs, Crumb("/user/0" => "new user");
        $page = 'user/0';
    }

    my $output = template 'user' => {
        edit              => $route_id,
        users             => \@users,
        groups            => $site->groups,
        register_requests => $register_requests,
        titles            => $users->titles,
        organisations     => $users->organisations,
        departments       => $users->departments,
        teams             => $users->teams,
        permissions       => $users->permissions,
        page              => $page,
        breadcrumbs       => \@breadcrumbs,
    };
    $output;
};

get '/helptext/:id?' => require_login sub {
    my $col_id = param 'id';
    my $column = $site->document->column($col_id);
    template 'helptext.tt', { column => $column }, { layout => undef };
};

get '/file/?' => require_login sub {

    $user->is_admin
        or forwardHome({ danger => "You do not have permission to manage files"}, '');

    template 'files' => {
        files       => $site->document->independent_files,
        breadcrumbs => [ Crumb("/file" => 'files') ],
    };
};

get '/file/:id' => require_login sub {
    my $set_id = is_valid_id(param 'id');

    # Need to get file details first, to be able to populate
    # column details of applicable.
    my $file_set = $site->document->file_set($set_id)
        or error __x"File set {id} cannot be found", id => $set_id;

    # In theory can be more than one, but not in practice (yet)
    my ($file_rs) = $file_set->files;

    my $file = GADS::Datum::File->new(ids => $set_id);
    # Get appropriate column, if applicable (could be unattached document)
    # This will control access to the file
    if ($file_rs && $file_rs->layout_id)
    {   my $column  = $site->document->column($file_rs->layout_id);
        $file->column($column);
    }
    elsif(!$file_set->is_independent)
    {   # If the file has been uploaded via a record edit and it hasn't been
        # attached to a record yet (or the record edit was cancelled) then do
        # not allow access
        my $owner_id = $file_set->edit_user_id;
        $owner_id && $owner_id == $user->id
            or error __x"Access to file {id} is not allowed", id => $file_id;
    }

    # Call content from the Datum::File object, which will ensure the user has
    # access to this file. The other parameters are taken straight from the
    # database resultset
    send_file(
        \($file->content),
        content_type => $file_set->mimetype,
        filename     => $file_set->name,
    );
};

post '/file/?' => require_login sub {

    my $ajax           = defined param('ajax');
    my $is_independent = defined param('is_independent') ? 1 : 0;

    if (my $upload = upload('file'))
    {
        my %insert = (
            name           => $upload->filename,
            mimetype       => $upload->type,
            content        => $upload->content,
            is_independent => $is_independent,
        );

        my $file_id;
        if(process( sub { $file_id = $site->document->file_create(%insert) }))
        {
            if($ajax)
            {   return encode_json({
                    id       => $file_id,
                    filename => $upload->filename,
                    url      => "/file/$file_id",
                    is_ok    => 1,
                });
            }
            else
            {   my $msg = __x"File has been uploaded as ID {id}", id => $file_id;
                return forwardHome( { success => "$msg" }, 'file' );
            }
        }
        elsif($ajax)
        {   return encode_json({ is_ok => 0, error => $@ });
        }
    }
    elsif($ajax)
    {   return encode_json({ is_ok => 0, error => "No file was submitted" });
    }
    else
    {   error __"No file submitted";
    }

};

get '/record_body/:id' => require_login sub {
    my $pointer_id = is_valid_id(param 'id');
    my $row  = $site->document->row(
        pointer_id => $pointer_id,
        rewind     => session('rewind'),
    );

    template 'record_body' => {
        is_modal       => 1, # Assume modal if loaded via this route
        record         => $row->presentation($sheet),
        has_rag_column => $row->has_rag_column,
        all_columns    => $row->columns_view,
    }, { layout => undef };
};

get qr{/(record|history|purge|purgehistory)/([0-9]+)} => require_login sub {
    my ($action, $id) = splat;
    my $doc = $sheet->document;

    my $id_type
      = $action eq 'history'      ? 'record_id'
      : $action eq 'purge'        ? 'deleted_currentid'
      : $action eq 'purgehistory' ? 'deleted_recordid'
      :                             'current_id';

    my $row = $doc->row($id_type => $id, rewind => session('rewind'));
    my $current_id = $row->current_id;

    if(defined param('pdf'))
    {   return send_file(
            \($row->pdf->content),
            content_type => 'application/pdf',
            filename     => "Record-$current_id.pdf"
        );
    }

    my $first_crumb = $action eq 'purge'
      ? Crumb($sheet, '/purge' => 'deleted records')
      : Crumb($sheet, '/data'  => 'records');

    my $output = template 'record' => {
        page           => 'record',
        record         => $row->presentation($sheet),
        versions       => [ $row->versions ],
        all_columns    => $row->columns_view,
        has_rag_column => $row->has_rag_column,
        is_history     => $action eq 'history',
        breadcrumbs    => [
            Crumb($sheet),
            $first_crumb,
            Crumb("/record/$current_id" => "record id $current_id"),
        ]
    };
    $output;
};

any ['get', 'post'] => '/audit/?' => require_role audit => sub {

    if(param 'audit_filtering')
    {   session audit_filtering => {
            method => param('method'),
            type   => param('type'),
            user   => param('user'),
            from   => param('from'),
            to     => param('to'),
        }
    }

    my $filter = session 'audit_filtering';
    my $audit = Linkspace::Audit->new;
    $audit->filtering($filter) if $filter;

    if (defined param 'download')
    {
        my $csv = $audit->csv;
        my $now = DateTime->now();
        my $header;
        if ($header = config->{gads}->{header})
        {
            $csv       = "$header\n$csv" if $header;
            $header    = "-$header" if $header;
        }
        # XXX Is this correct? We can't send native utf-8 without getting the error
        # "Strings with code points over 0xFF may not be mapped into in-memory file handles".
        # So, encode the string (e.g. "\x{100}"  becomes "\xc4\x80) and then send it,
        # telling the browser it's utf-8
        utf8::encode($csv);
        return send_file( \$csv, content_type => 'text/csv; charset="utf-8"', filename => "$now$header.csv" );
    }

    template audit => {
        logs        => $audit->logs($filter),
        users       => $site->users,
        filtering   => $filter,
        audit_types => $audit->audit_types,
        page        => 'audit',
        breadcrumbs => [Crumb("/audit" => 'audit logs')],
    };
};


get '/logout' => sub {
    app->destroy_session;
    $::session->user_logout;
    $::session = $::linkspace->default_session;
    forwardHome();
};

any ['get', 'post'] => '/resetpw/:code' => sub {

    # Strange things happen if running this code when already logged in.
    # Log the existing user out first
    if(logged_in_user)
    {   app->destroy_session;
        _update_csrf_token();
    }

    # Perform check first in order to get user ID for audit
    if (my $username = user_password code => param('code'))
    {
        my $new_password;

        if (param 'execute_reset')
        {
            app->destroy_session;

            my $user   = $site->users->user(username => $username);
            # Now we know this user is genuine, reset any failure that would
            # otherwise prevent them logging in
            $user->update({ failcount => 0 });
            $::session->audit("Password reset performed for user ID ".$user->id,
                type => 'login_change',
            );

            $new_password = _random_pw();
            user_password code => param('code'), new_password => $new_password;
            _update_csrf_token();
        }

        return template login => {
            site_name  => $site->name || 'Linkspace',
            reset_code => 1,
            password   => $new_password,
            page       => 'login',
        };
    }

    return forwardHome({ danger =>
         qq(The password reset code is not valid. Please request a new one using the "Reset Password" link)}, 'login'
    );
};

get '/invalidsite' => sub {
    template 'invalidsite' => {
        page => 'invalidsite'
    };
};

prefix '/:layout_name' => sub {

    get '/?' => require_login sub {

        my $dashboard_id;
        if ($dashboard_id = query_parameters->get('did'))
        {   session('persistent')->{dashboard}{$sheet->id} = $dashboard_id;
        }
        else
        {   $dashboard_id = session('persistent')->{dashboard}{$sheet->id};
        }

        my %params = (
            id     => $dashboard_id,
            user   => $user,
            layout => $layout,
            site   => $site,
        );

        my $dashboard = $::db->resultset('Dashboard')->dashboard(%params);

        # If the shared dashboard is blank for this table then show the site
        # dashboard by default
        if ($dashboard->is_shared && $dashboard->is_empty && !$dashboard_id)
        {
            my %params = (
                user   => $user,
                site   => $site,
            );
            $dashboard = $::db->resultset('Dashboard')->dashboard(%params);
        }

        my $params = {
            readonly        => $dashboard->is_shared && !$sheet->user_can('layout'),
            dashboard       => $dashboard,
            dashboards_json => $::db->resultset('Dashboard')->dashboards_json(%params),
            page            => 'index',
            breadcrumbs     => [ Crumb($sheet) ],
        };

        if (my $download = param('download'))
        {
            $params->{readonly} = 1;
            if ($download eq 'pdf')
            {
                my $pdf = _page_as_mech('index', $params, pdf => 1)->content_as_pdf;
                return send_file(
                    \$pdf,
                    content_type => 'application/pdf',
                );
            }
        }

        template 'index' => $params;
    };

    get '/data_calendar/:time' => require_login sub {

        my $layout = var('layout') or pass;

        # Time variable is used to prevent caching by browser

        my $fromdt  = DateTime->from_epoch( epoch => ( param('from') / 1000 ) );
        my $todt    = DateTime->from_epoch( epoch => ( param('to') / 1000 ) );

        # Attempt to find period requested. Sometimes the duration is
        # slightly less than expected, hence the multiple tests
        my $diff     = $todt->subtract_datetime($fromdt);
        my $dt_view
           = ($diff->months >= 11 || $diff->years)  ? 'year'
           : ($diff->weeks > 1    || $diff->months) ? 'month'
           : ($diff->days >= 6    || $diff->weeks)  ? 'week'
           :                                          'day'; # Default to month

        # Attempt to remember day viewed. This is difficult, due to the
        # timezone issues described below. XXX How to fix?
        session 'calendar' => {
            day  => $todt->clone->subtract(days => 1),
            view => $dt_view,
        };

        # Epochs received from the calendar module are based on the timezone of the local
        # browser. So in BST, 24th August is requested as 23rd August 23:00. Rather than
        # trying to convert timezones, we keep things simple and round down any "from"
        # times and round up any "to" times.
        $fromdt->truncate( to => 'day');
        if ($todt->hms('') ne '000000')
        {
            # If time is after midnight, round down to midnight and add day
            $todt->set(hour => 0, minute => 0, second => 0);
            $todt->add(days => 1);
        }

        if ($fromdt->hms('') ne '000000')
        {
            # If time is after midnight, round down to midnight
            $fromdt->set(hour => 0, minute => 0, second => 0);
        }

        my $records = GADS::Records->new(
            user                => $user,
            layout              => $layout,
            view                => current_view(),
            search              => session('search'),
            view_limit_extra_id => current_view_limit_extra_id(),
        );

        header "Cache-Control" => "max-age=0, must-revalidate, private";
        content_type 'application/json';
        my $data = $records->data_calendar(
            from => $fromdt,
            to   => $todt,
        );
        encode_json({
            "success" => 1,
            "result"  => $data,
        });
    };

    get '/data_timeline/:time' => require_login sub {

        # Time variable is used to prevent caching by browser
        my $fromdt = DateTime->from_epoch( epoch => int (param('from')/1000) );
        my $todt   = DateTime->from_epoch( epoch => int (param('to')  /1000) );

        my $records = GADS::Records->new(
            from                => $fromdt,
            to                  => $todt,
            exclusive           => param('exclusive'),
            view                => current_view(),
            search              => session('search'),
            rewind              => session('rewind'),
            view_limit_extra_id => current_view_limit_extra_id(),
        );

        header "Cache-Control" => "max-age=0, must-revalidate, private";
        content_type 'application/json';

        my $tl_options = session('persistent')->{tl_options}{$sheet->id} || {};
        my $timeline = $records->data_timeline(%$tl_options);
        encode_json($timeline->{items});
    };

    post '/data_timeline' => require_login sub {

        my $view               = current_view();
        my $tl_options         = session('persistent')->{tl_options}{$sheet->id} ||= {};
        $tl_options->{from}    = int(param('from') /1000) if param('from');
        $tl_options->{to}      = int(param('to')   /1000) if param('to');

        $tl_options->{view_id} = $view && $view->id;
        # Note the current time so that we can decide later if it's relevant to
        # load these settings
        $tl_options->{now}     = DateTime->now->epoch;

        # XXX Application session settings do not seem to be updated without
        # calling template (even calling _update_persistent does not help)
        return template 'index' => {};
    };

    get '/data_graph/:id/:time' => require_login sub {

        my $graph_id = is_valid_id(param 'id');
        my $gdata    = _data_graph($graph_id);

        header "Cache-Control" => "max-age=0, must-revalidate, private";
        content_type 'application/json';
        encode_json({
            points  => $gdata->points,
            labels  => $gdata->labels_encoded,
            xlabels => $gdata->xlabels,
            options => $gdata->options,
        });
    };

    any ['get', 'post'] => '/data' => require_login sub {

        # Check for bulk delete
        if (param 'modal_delete')
        {
            $sheet->user_can("delete")
               or error __"You do not have permission to delete records";

            my %params = (
                user                => $user,
                search              => session('search'),
                layout              => $layout,
                rewind              => session('rewind'),
                view                => current_view(),
                view_limit_extra_id => current_view_limit_extra_id(),
            );

            my @delete_ids = body_parameters->get_all('delete_id');
            $params{limit_current_ids} = \@delete_ids
                if @delete_ids;

            my $records = GADS::Records->new(%params);

            my $count; # Count actual number deleted, not number reported by search result

            while (my $record = $records->single)
            {
                $count++ if process sub { $record->delete_current };
            }
            return forwardHome(
                { success => "$count records successfully deleted" }, $sheet->identifier.'/data' );
        }

        app->execute_hook( 'plugin.data.before_request', user => $user )
            if app->has_hook('plugin.data.before_request');

        # Check for rewind configuration
        if (param('modal_rewind') || param('modal_rewind_reset'))
        {
            if(param('modal_rewind_reset') || !param('rewind_date'))
            {   session rewind => undef;
            }
            else
            {   my $input = param('rewind_date');
                          . ' ' . (param'rewind_time') || '23:59:59');
                my $dt    = $::session->user->local2dt($input)
                    or error __x"Invalid date or time: {datetime}", datetime => $input;
                session rewind => $dt;
            }
        }

        # Search submission or clearing a search?
        if(defined(param('search_text')) || defined(param 'clear_search'))
        {
            error __"Not possible to conduct a search when viewing data on a previous date"
                if session('rewind');

            my $search  = param('clear_search') ? '' : param('search_text');
            $search =~ s/\h+$//;
            $search =~ s/^\h+//;
            session 'search' => $search;
            if ($search)
            {
                my $records = GADS::Records->new(
                    search              => $search,
                    view_limit_extra_id => current_view_limit_extra_id(),
                );
                my $results = $records->current_ids;

                # Redirect to record if only one result
                redirect "/record/$results->[0]"
                    if @$results == 1;
            }
        }

        # Setting a new view limit extra
        if (my $extra = $sheet->user_can('view_limit_extra') && param('extra'))
        {
            session('persistent')->{view_limit_extra}{$sheet->id} = $extra;
        }

        my $new_view_id = param('view');
        if (param 'views_other_user_clear')
        {   session views_other_user_id => undef;
            $new_view_id = $sheet->views->default->id;
        }
        elsif (my $user_id = param 'views_other_user_id')
        {   session views_other_user_id => $user_id;
        }

        # Deal with any alert requests
        if (param 'modal_alert')
        {
            if(my $view = $sheet->views->view(param 'view_id'))
            {   if(process(sub {
                    $view->create_alert(frequency => param('frequency'));
                }))
                {
                    return forwardHome({ success =>
                        "The alert has been saved successfully" }, $sheet->identifier.'/data' );
                }
            }
        }

        if ($new_view_id)
        {
            session('persistent')->{view}{$sheet->id} = $new_view_id;

            # Save to database for next login.
            # Check that it's valid first, otherwise database will bork
            my $view = current_view();

            # When a new view is selected, unset sort, otherwise it's
            # not possible to remove a sort once it's been clicked
            session 'sort' => undef;
            session 'page' => undef; # Also reset page number to 1
            session search => '';    # And remove any search to avoid confusion
        }

        if(my $rows = param('rows'))
        {   session 'rows' => int $rows;
        }

        if (my $page = param('page'))
        {   session 'page' => int $page;
        }

        my $viewtype;
        if($viewtype = param('viewtype'))
        {   session('persistent')->{viewtype}{$sheet->id} = $viewtype
                if $viewtype =~ /^(graph|table|calendar|timeline|globe)$/;
        }
        else
        {   $viewtype = session('persistent')->{viewtype}{$sheet->id} || 'table';
        }

        my $view       = current_view();

        my $params = { };

        if ($viewtype eq 'graph')
        {
            $params->{page}     = 'data_graph';
            $params->{viewtype} = 'graph';
            if (my $png = param 'png')
            {
                my $gdata = _data_graph($png);
                my $json  = $gdata->as_json;
                my $graph = GADS::Graph->new(
                    id     => $png,
                    layout => $layout,
                );
                my $options_in = $graph->as_json;
                $params->{graph_id} = $png;

                my $mech = _page_as_mech('data_graph', $params, width => 630, height => 400);
                $mech->eval_in_page('(function(plotData, options_in){do_plot_json(plotData, options_in)})(arguments[0],arguments[1]);',
                    $json, $options_in
                );

                my $png= $mech->content_as_png();
                # Send as inline images to make copy and paste easier
                return send_file(
                    \$png,
                    content_type        => 'image/png',
                    content_disposition => 'inline', # Default is attachment
                );
            }
            elsif (my $csv = param('csv'))
            {
                my $graph = GADS::Graph->new(
                    id     => $csv,
                    layout => $layout,
                    schema => schema
                );
                my $gdata       = _data_graph($csv);
                my $csv_content = $gdata->csv;
                return send_file(
                    \$csv_content,
                    content_type => 'text/csv',
                    filename     => "graph".$graph->id.".csv",
                );
            }
            else {
                $params->{graphs} = GADS::Graphs->new(current_user => $user, schema => schema, layout => $layout)->all;
            }
        }
        elsif ($viewtype eq 'calendar')
        {
            # Get details of the view and work out color markers for date fields
            my $records = GADS::Records->new(
                user    => $user,
                layout  => $layout,
                schema  => schema,
            );
            my @columns = @{$records->columns_view};
            my @colors;
            my $graph = GADS::Graph::Data->new(
                schema  => schema,
                records => undef,
            );

            foreach my $column (@columns)
            {
                if ($column->type eq "daterange" || ($column->return_type && $column->return_type eq "date"))
                {
                    my $color = $graph->get_color($column->name);
                    push @colors, { key => $column->name, color => $color};
                }
            }

            $params->{calendar} = session('calendar'); # Remember previous day viewed
            $params->{colors}   = \@colors;
            $params->{page}     = 'data_calendar';
            $params->{viewtype} = 'calendar';
        }
        elsif ($viewtype eq 'timeline')
        {
            my $records = GADS::Records->new(
                view                => $view,
                search              => session('search'),
                layout              => $layout,
                # No "to" - will take appropriate number from today
                from                => DateTime->now, # Default
                rewind              => session('rewind'),
                view_limit_extra_id => current_view_limit_extra_id(),
            );
            my $tl_options = session('persistent')->{tl_options}{$sheet_id} ||= {};
            if (param 'modal_timeline')
            {
                $tl_options->{label}   = param('tl_label');
                $tl_options->{group}   = param('tl_group');
                $tl_options->{color}   = param('tl_color');
                $tl_options->{overlay} = param('tl_overlay');
            }

            # See whether to restore remembered range
            if (
                defined $tl_options->{from}   # Remembered range exists?
                && defined $tl_options->{to}
                && ((!$tl_options->{view_id} && !$view) || ($view && $tl_options->{view_id} == $view->id)) # Using the same view
                && $tl_options->{now} > DateTime->now->subtract(days => 7)->epoch # Within sensible window
            )
            {
                $records->from(DateTime->from_epoch(epoch => $tl_options->{from}));
                $records->to(DateTime->from_epoch(epoch => $tl_options->{to}));
            }

            my $timeline = $records->data_timeline(%{$tl_options});
            $params->{records}      = encode_base64(encode_json(delete $timeline->{items}), '');
            $params->{groups}       = encode_base64(encode_json(delete $timeline->{groups}), '');
            $params->{colors}       = delete $timeline->{colors};
            $params->{timeline}     = $timeline;
            $params->{tl_options}   = $tl_options;
            $params->{columns_read} = [ $layout->search_columns(user_can_read => 1) ];
            $params->{page}         = 'data_timeline';
            $params->{viewtype}     = 'timeline';
            $params->{search_limit_reached} = $records->search_limit_reached;

            if (my $png = param('png'))
            {
                my $png = _page_as_mech('data_timeline', $params)->content_as_png;
                return send_file(
                    \$png,
                    content_type => 'image/png',
                );
            }
            if (param('modal_pdf'))
            {
                $tl_options->{pdf_zoom} = param('pdf_zoom');
                my $pdf = _page_as_mech('data_timeline', $params, pdf => 1, zoom => $tl_options->{pdf_zoom})->content_as_pdf;
                return send_file(
                    \$pdf,
                    content_type => 'application/pdf',
                );
            }
        }
        elsif ($viewtype eq 'globe')
        {
            my $globe_options = session('persistent')->{globe_options}->{$layout->instance_id} ||= {};
            if (param 'modal_globe')
            {
                $globe_options->{group} = param('globe_group');
                $globe_options->{color} = param('globe_color');
                $globe_options->{label} = param('globe_label');
            }

            my $records_options = {
                user   => $user,
                view   => $view,
                search => session('search'),
                layout => $layout,
                schema => schema,
                rewind => session('rewind'),
            };
            my $globe = GADS::Globe->new(
                group_col_id    => $globe_options->{group},
                color_col_id    => $globe_options->{color},
                label_col_id    => $globe_options->{label},
                records_options => $records_options,
            );
            $params->{globe_data} = encode_base64(encode_json($globe->data), '');
            $params->{colors}               = $globe->colors;
            $params->{globe_options}        = $globe_options;
            $params->{columns_read}         = [$layout->columns_for_filter];
            $params->{viewtype}             = 'globe';
            $params->{page}                 = 'data_globe';
            $params->{search_limit_reached} = $globe->records->search_limit_reached;
            $params->{count}                = $globe->records->count;
        }
        else {
            session 'rows' => 50 unless session 'rows';
            session 'page' => 1 unless session 'page';

            my $rows = defined param('download') ? undef : session('rows');
            my $page = defined param('download') ? undef : session('page');

            my @additional;
            foreach my $key (keys %{query_parameters()})
            {
                $key =~ /^field([0-9]+)$/
                    or next;
                my $fid = $1;
                my @values = query_parameters->get_all($key);
                push @additional, {
                    id    => $fid,
                    value => [query_parameters->get_all($key)],
                };
            }

            my %params = (
                user                => $user,
                search              => session('search'),
                layout              => $layout,
                schema              => schema,
                rewind              => session('rewind'),
                additional_filters  => \@additional,
                view_limit_extra_id => current_view_limit_extra_id(),
            );
            # If this is a filter from a group view, then disable the group for
            # this rendering
            $params{is_group} = 0 if defined query_parameters->get('group_filter') && @additional;

            my $records = GADS::Records->new(%params);

            $records->view($view);
            $records->rows($rows);
            $records->page($page);
            $records->sort(session 'sort');

            if (param('sort') && param('sort') =~ /^([0-9]+)(asc|desc)$/)
            {
                my $sortcol  = $1;
                my $sorttype = $2;
                # Check user has access
                forwardHome({ danger => "Invalid column ID for sort" }, $sheet->identifier.'/data')
                    unless $layout->column($sortcol) && $layout->column($sortcol)->user_can('read');
                my $existing = $records->sort_first;
                my $type;
                session 'sort' => { type => $sorttype, id => $sortcol };
                $records->clear_sorts;
                $records->sort(session 'sort');
            }

            if (param 'modal_sendemail')
            {
                forwardHome({ danger => "There are no records in this view and therefore nobody to email"}, $sheet->identifier.'/data')
                    unless $records->results;

                return forwardHome(
                    { danger => 'You do not have permission to send messages' }, $sheet->identifier.'/data' )
                    unless $sheet->user_can("message");

                if(process( sub {
                    $::linkspace->mailer->message(
                    subject => param('subject'),
                    text    => param('text'),
                    records => $records,
                    col_id  => param('peopcol'),
                ) }))
                {
                    return forwardHome(
                        { success => "The message has been sent successfully" }, $sheet->identifier.'/data' );
                }
            }

            if (defined param('download'))
            {
                forwardHome({ danger => "There are no records to download in this view"}, $sheet->identifier.'/data')
                    unless $records->count;

                # Return CSV as a streaming response, otherwise a long delay whilst
                # the CSV is generated can cause a client to timeout
                return delayed {
                    # XXX delayed() does not seem to use normal Dancer error
                    # handling - make sure any fatal errors are caught
                    try {
                        my $now = DateTime->now;
                        my $header = config->{gads}->{header} || '';
                        $header = "-$header" if $header;
                        header 'Content-Disposition' => "attachment; filename=\"$now$header.csv\"";
                        content_type 'text/csv; charset="utf-8"';

                        flush; # Required to start the async send
                        content $records->csv_header;

                        while ( my $row = $records->csv_line ) {
                            utf8::encode($row);
                            content $row;
                        }
                        done;
                    } accept => 'WARNING-'; # Don't collect the thousands of trace messages
                    # Not ideal, but throw exceptions somewhere...
                    say STDERR "$@" if $@;
                } on_error => sub {
                    # This doesn't seen to get called
                    say STDERR "Failed to stream: @_";
               };
            }

            my $pages = $records->pages;

            my $subset = {
                rows  => session('rows'),
                pages => $pages,
                page  => $page,
            };
            if ($pages > 50)
            {
                my @pnumbers = (1..5);
                if ($page-5 > 6)
                {
                    push @pnumbers, '...';
                    my $max = $page + 5 > $pages ? $pages : $page + 5;
                    push @pnumbers, ($page-5..$max);
                }
                else {
                    push @pnumbers, (6..15);
                }
                if ($pages-5 > $page+5)
                {
                    push @pnumbers, '...';
                    push @pnumbers, ($pages-4..$pages);
                }
                elsif ($pnumbers[-1] < $pages)
                {
                    push @pnumbers, ($pnumbers[-1]+1..$pages);
                }
                $subset->{pnumbers} = [@pnumbers];
            }
            else {
                $subset->{pnumbers} = [1..$pages];
            }

            my @columns = @{$records->columns_view};
            $params->{user_can_edit}        = $sheet->user_can('write_existing');
            $params->{sort}                 = $records->sort_first;
            $params->{subset}               = $subset;
            $params->{records}              = $records->presentation;
            $params->{aggregate}            = $records->aggregate_presentation;
            $params->{count}                = $records->count;
            $params->{columns}              = [ map $_->presentation(
                sort             => $records->sort_first,
                filters          => \@additional,
                query_parameters => query_parameters,
            ), @columns ];
            $params->{is_group}             = $records->is_group,
            $params->{has_rag_column}       = $records->has_rag_column;
            $params->{viewtype}             = 'table';
            $params->{page}                 = 'data_table';
            $params->{search_limit_reached} = $records->search_limit_reached;

            if (@additional)
            {
                # Should be moved into presentation layer
                my @filters;
                foreach my $add (@additional)
                {
                    push @filters, "field$add->{id}=".uri_escape_utf8($_)
                        foreach @{$add->{value}};
                }
                $params->{filter_url} = join '&', @filters;
            }
        }

        if ( app->has_hook('plugin.data.before_template') ) {
            # Note: this might modify $params
            app->execute_hook('plugin.data.before_template', {
                user   => $user,
                layout => $layout,
                params => $params,
            });
        }

        my $views     = $sheet->views;
        $params->{user_views}        = $views->user_views($user);
        $params->{views_limit_extra} = $views->views_limit_extra
             if $user->user_can('view_limit_extra');

        $params->{current_view_limit_extra} = current_view_limit_extra();
        $params->{alerts}            = Layout::View::Alert->for_user;
        $params->{views_other_user}  = $users->user(session 'views_other_user_id');

        $params->{breadcrumbs}              = [
            Crumb($sheet) =>
            Crumb($sheet, '/data' => 'records')
        ];

        template 'data' => $params;
    };

    # any ['get', 'post'] => qr{/tree[0-9]*/([0-9]*)/?} => require_login sub {
    any ['get', 'post'] => '/tree:any?/:layout_id/?' => require_login sub {
        # Random number can be used after "tree" to prevent caching

        my ($layout_id) = splat;  #XXX?
        $layout_id = route_parameters->get('layout_id');

        my $tree = $sheet->layout->column($layout_id)
            or error __x"Invalid tree ID {id}", id => $layout_id;

        if (param 'data')
        {
            return forwardHome(
                { danger => 'You do not have permission to edit trees' } )
                unless $sheet->user_can("layout");

            my $newtree = JSON->new->utf8(0)->decode(param 'data');
            $tree->update($newtree);
            return;
        }
        my @ids  = query_parameters->get_all('ids');
        my $json = $tree->type eq 'tree' ? $tree->json(@ids) : [];

        # If record is specified, select the record's value in the returned JSON
        header "Cache-Control" => "max-age=0, must-revalidate, private";
        content_type 'application/json';
        encode_json($json);

    };

    any ['get', 'post'] => '/purge/?' => require_login sub {

        $sheet->user_can("purge")
            or forwardHome({ danger => "You do not have permission to manage deleted records"}, '');

        if (param('purge') || param('restore'))
        {
            my @current_ids = body_parameters->get_all('record_selected')
                or forwardHome({ danger => "Please select some records before clicking an action" }, $sheet->identifier.'/purge');

            my $records = GADS::Records->new(
                limit_current_ids   => \@current_ids,
                columns             => [],
                is_deleted          => 1,
                view_limit_extra_id => undef, # Override any value that may be set
            );

            if (param 'purge')
            {
                my $record;
                $record->purge_current while $record = $records->single;
                forwardHome({ success => "Records have now been purged" }, $sheet->identifier.'/purge');
            }

            if (param 'restore')
            {
                my $record;
                $record->restore while $record = $records->single;
                forwardHome({ success => "Records have now been restored" }, $sheet->identifier.'/purge');
            }
        }

        my $records = GADS::Records->new(
            columns             => [],
            is_deleted          => 1,
            view_limit_extra_id => undef, # Override any value that may be set
        );

        my $params = {
            page    => 'purge',
            records => $records->presentation($sheet, purge => 1),
        };

        $params->{breadcrumbs} = [
            Crumb($sheet) =>
            Crumb($sheet, '/data' => 'records') =>
            Crumb($sheet, '/purge' => 'purge records')
        ];

        template 'purge' => $params;
    };

    any ['get', 'post'] => '/graph/:id' => require_login sub {
        my $graph_id = is_valid_id(param 'id');

        my $params = {
            layout => $layout,
            page   => 'graph',
        };

        my $graph = GADS::Graph->new(
            id           => $graph_id,
            layout       => $layout,
            current_user => $user,
        );

        if (param 'delete')
        {
            if (process( sub { $graph->delete }))
            {
                return forwardHome(
                    { success => "The graph has been deleted successfully" }, $sheet->identifier.'/graphs' );
            }
        }

        if (param 'submit')
        {
            my $values = params;
            $graph->$_(param $_)
                foreach (qw/title description type set_x_axis x_axis_grouping y_axis
                    y_axis_label y_axis_stack group_by stackseries metric_group_id as_percent
                    is_shared group_id trend from to x_axis_range/);

            if(process( sub { $graph->write }))
            {
                my $action = $graph_id ? 'updated' : 'created';
                return forwardHome(
                    { success => "Graph has been $action successfully" }, $sheet->identifier.'/graphs' );
            }
        }

        $params->{graph}         = $graph;
        $params->{metric_groups} = GADS::MetricGroups->new(
            instance_id => session('persistent')->{instance_id},
        )->all;

        my $graph_name = $id ? $graph->title : "add a graph";
        my $graph_id   = $id ? $graph->id : 0;
        $params->{breadcrumbs}   = [
            Crumb($sheet) => Crumb($sheet, '/data' => 'records')
                => Crumb($sheet, '/graphs' => 'graphs') => Crumb($sheet, "/graph/$graph_id" => $graph_name)
        ],

        template 'graph' => $params;
    };

    get '/metrics/?' => require_login sub {

        $sheet->user_can("layout")
            or forwardHome({ danger => "You do not have permission to manage metrics" }, '');

        template 'metrics' => {
            layout      => $sheet,
            page        => 'metric',
            metrics     => $sheet->metrics->all_groups,
            breadcrumbs => [
                Crumb($sheet),
                Crumb($sheet, '/data'    => 'records'),
                Crumb($sheet, '/graphs'  => 'graphs' ),
                Crumb($sheet, '/metrics' => 'metrics'),
            ],
        };

    };

    any ['get', 'post'] => '/metric/:id' => require_login sub {
        my $mg_id     = is_valid_id(param 'id');
        my $metric_id = is_valid_id(param 'metric_id');

        $sheet->user_can("layout")
            or forwardHome({ danger => "You do not have permission to manage metrics" }, '');

        my $metrics     = $sheet->metrics;
        my $metricgroup = $metrics->group($mg_id);

        if (param 'delete_all')
        {
            if (process( sub { $metricgroup->delete }))
            {
                return forwardHome(
                    { success => "The metric has been deleted successfully" }, $sheet->identifier.'/metrics' );
            }
        }

        # Delete an individual item from a group
        if (param 'delete_metric')
        {
            if (process( sub { $metricgroup->delete_metric($metric_id) }))
            {
                return forwardHome(
                    { success => "The metric has been deleted successfully" }, $sheet->identifier."/metric/$mg_id" );
            }
        }

        if (param 'submit')
        {
            $metricgroup->name(param 'name');
            if(process( sub { $metricgroup->write }))
            {
                my $action = $mg_id ? 'updated' : 'created';
                return forwardHome(
                    { success => "Metric has been $action successfully" }, $sheet->identifier.'/metrics' );
            }
        }

        # Update/create an individual item in a group
        if (param 'update_metric')
        {   my @data = (
                x_axis_value          => param('x_axis_value'),
                y_axis_grouping_value => param('y_axis_grouping_value'),
                target                => param('target'),
            );

            my $action;
            if(process( sub {
               if($metric_id)
               {   $metricgroup->metric_update($metric_id => @data);
                   $action    = 'updated';
               }
               else
               {   $metric_id = $metricgroup->metric_create(@data);
                   $action    = 'created';
               }
             }))
            {
                return forwardHome(
                    { success => "Metric has been $action successfully" }, $sheet->identifier."/metric/$mg_id" );
            }
        }


        my @breadcrumbs = (
            Crumb($sheet),
            Crumb($sheet, '/data' => 'records'),
            Crumb($sheet, '/graphs' => 'graphs'),
            Crumb($sheet, '/metrics' => 'metrics'),
        );

        push @breadcrumbs, $mg_id
          ? Crumb($sheet, "/metric/$mg_id" => $metricgroup->name)
          : Crumb($sheet, "/metric/0"      => 'add a metric');

        template 'metric' => {
            page        => 'metric',
            layout      => $layout,
            metricgroup => $metricgroup,
            breadcrumbs => \@breadcrumbs,
        };
    };

    any ['get', 'post'] => '/topic/:id' => require_login sub {

        my $layout = var('layout') or pass;

        my $user        = logged_in_user;

        my $instance_id = $layout->instance_id;

        forwardHome({ danger => "You do not have permission to manage topics"}, '')
            unless $sheet->user_can("layout");

        my $id = param 'id';
        my $topic = $id && schema->resultset('Topic')->search({
            id          => $id,
            instance_id => $instance_id,
        })->next;

        if (param 'submit')
        {
            $topic = schema->resultset('Topic')->new({ instance_id => $instance_id })
                if !$id;

            $topic->name(param 'name');
            $topic->description(param 'description');
            $topic->click_to_edit(param 'click_to_edit');
            $topic->initial_state(param 'initial_state');
            $topic->prevent_edit_topic_id(param('prevent_edit_topic_id') || undef);

            if (process(sub {$topic->update_or_insert}))
            {
                my $action = param('id') ? 'updated' : 'created';
                return forwardHome(
                    { success => "Topic has been $action successfully" }, $sheet->identifier.'/topics' );
            }
        }

        if (param 'delete_topic')
        {
            if (process(sub {$topic->delete}))
            {
                return forwardHome(
                    { success => "The topic has been deleted successfully" }, $sheet->identifier.'/topics' );
            }
        }

        my $topic_name = $id ? $topic->name : 'new topic';
        my $topic_id   = $id ? $topic->id : 0;
        template 'topic' => {
            topic       => $topic,
            topics      => [schema->resultset('Topic')->search({ instance_id => $instance_id })->all],
            breadcrumbs => [Crumb($sheet) => Crumb($sheet, '/topics' => 'topics') => Crumb($sheet, "/topic/$topic_id" => $topic_name)],
            page        => !$id ? 'topic/0' : 'topics',
        }
    };

    get '/topics/?' => require_login sub {

        my $layout = var('layout') or pass;

        my $user        = logged_in_user;

        my $instance_id = $layout->instance_id;

        forwardHome({ danger => "You do not have permission to manage topics"}, '')
            unless $sheet->user_can("layout");

        template 'topics' => {
            layout      => $layout,
            topics      => [schema->resultset('Topic')->search({ instance_id => $instance_id })->all],
            breadcrumbs => [Crumb($sheet) => Crumb($sheet, '/topics' => 'topics')],
            page        => 'topics',
        };
    };

    any ['get', 'post'] => '/view/:id' => require_login sub {

        $sheet->user_can("view_create")
            or return forwardHome( { danger => 'You do not have permission to edit views' }, $sheet->identifier.'/data' );

        my $view_id = param 'id';
        $view_id =~ /^[0-9]+$/
            or error __x"Invalid view ID: {id}", id => $view_id;

        my $is_new   = defined $view_id && $view_id==0;
        my $clone_id = param 'clone';
        my $is_clone = request->is_post ? 0 : !!$clone_id;
        $view_id = $clone_id if $is_clone;

        my (@ucolumns, $view_values);

        my $view = $sheet->views->view($view_id);

        # If this is a clone of a full global view, but the user only has group
        # view creation rights, then remove the global parameter, otherwise it
        # means that it is ticked by default but only for a group instead

        my $global = $param('global') ? 1 : 0;
        $global = 0
            if param('clone')
            && !$view->group_id
            && !$sheet->user_can('layout');

        if (param 'update')
        {
            #XXX other_user_id => session('views_other_user_id'),
            #XXX not needed anymore?

            my $name = param('name');
            if(process sub{ $view->update(
                sheet      => $sheet,
                column_ids => param('column'),
                global     => $global,
                is_admin   => param('is_admin') ? 1 : 0,
                group_id   => param('group_id'),
                name       => $name,
                sortfields => [ body_parameters->get_all('sortfield') ],
                sorttypes  => [ body_parameters->get_all('sorttype')  ],
                groups     => [ body_parameters->get_all('groupfield') ],
                filter     => param('filter'),
            ) } )
            {
                # Set current view to the one created/edited
                session('persistent')->{view}{$sheet->id} = $view->id;
                session search => ''; # remove any search to avoid confusion

                # And remove any custom sorting, so that sort of view takes effect
                session 'sort' => undef;

                return forwardHome(
                    { success => "The view has been updated successfully" }, $sheet->identifier.'/data' );
            }
        }
        elsif (param 'delete')
        {
            if(process( sub { $view->delete($sheet) }))
            {   session('persistent')->{view}{$sheet->id} = undef;
                return forwardHome(
                    { success => "The view has been deleted successfully" }, $sheet->identifier.'/data' );
            }
        }

        my $page
            = $is_clone ? 'view/clone'
            : $is_new   ? 'view/0'
            :             'view';

        my @breadcrumbs = (
           Crumb($sheet),
           Crumb($sheet, '/data' => 'records'),
        );
        push @breadcrumbs,
           Crumb($sheet, "/view/0?clone=$view_id" => 'clone view "$name"')
           if $is_clone;

        push @breadcrumbs, Crumb($sheet, "/view/$view_id" => 'edit view "$name"')
            if $view_id && ! $is_clone

        push @breadcrumbs, Crumb($sheet, "/view/0" => 'new view')
            if !$view_id && defined $view_id;

        my $output = template 'view' => {
            layout      => $layout,
            sort_types  => $view->sort_types,
            view_edit   => $view, # TT does not like variable "view"
            clone       => $clone_id,  #XXX or $is_clone
            page        => $page,
            breadcrumbs => \@breadcrumbs,
        };

        $output;
    };

    any ['get', 'post'] => '/layout/?:id?' => require_login sub {
        my $col_id = is_valid_id(param 'id');

        $sheet->user_can('layout')
            or forwardHome({ danger => "You do not have permission to manage fields"}, '')

        my $params = {
            page => defined $col_id && $col_id==0 ? 'layout/0' : 'layout',
            all_columns => $sheet->layout->columns,
        };

        if($col_id)
        {
            # Get all layouts of all instances for field linking
            $params->{instance_layouts} = var('instances')->all;
            $params->{instances_object} = var('instances'); # For autocur. Don't conflict with other instances var
        }

        my @breadcrumbs = (
            Crumb($sheet),
            Crumb($sheet, '/layout' => 'fields');
        );

        if($col_id || param('submit') || param('update_perms'))
        {
            my $column;
            if($col_id)
            {   $column = $layout->column($col_id)
                    or error __x"Column ID {id} not found", id => $col_id;
            }
            else
            {   my $class = param('type');
                first {$class eq $_} GADS::Column::types
                    or error __x"Invalid column type {class}", class => $class;
                $class = "GADS::Column::".camelize($class);
                $column = $class->new(
                    user   => $user,
                    layout => $layout
                );
            }

            if (param 'delete')
            {
                # Provide plenty of logging in case of repercussions of deletion
                my $colname = $column->name;
                trace __x"Starting deletion of column {name}", name => $colname;
                $::session->audit(qq(User "$username" deleted field "$colname"));
                if (process( sub { $column->delete }))
                {
                    return forwardHome(
                        { success => "The item has been deleted successfully" }, $sheet->identifier.'/layout' );
                }
            }

            if (param 'submit')
            {
                my %permissions;

                foreach (keys %{ params() }) {
                    my ($name, $group_id) = m/^permission_(.*?)_(\d+)$/ or next;
                    push @{ $permissions{$group_id} ||= [] }, $name;
                }

                $column->set_permissions(\%permissions);

                $column->$_(param $_)
                    foreach (qw/name name_short description helptext optional isunique set_can_child
                        multivalue remember link_parent_id topic_id width aggregate group_display/);
                $column->type(param 'type')
                    unless $col_id; # Can't change type as it would require DBIC resultsets to be removed and re-added

                $column->$_(param $_)
                    foreach @{$column->option_names};

                $column->display_fields(param 'display_fields');
                # Set the layout in the GADS::Filter object, in case the write
                # doesn't success, in which case the filter will need to be
                # turned into base64 which requires layout to be set in
                # GADS::Filter (to prevent a panic)
                $column->display_fields->layout($layout);

                my $no_alerts;
                if ($column->type eq "file")
                {   $column->filesize(param('filesize') || undef);
                }
                elsif ($column->type eq "rag")
                {
                    $column->code(param 'code_rag');
                    $no_alerts = param('no_alerts_rag');
                }
                elsif ($column->type eq "enum")
                {
                    my $params = params;
                    $column->enumvals({
                        enumvals    => [body_parameters->get_all('enumval')],
                        enumval_ids => [body_parameters->get_all('enumval_id')],
                    });
                    $column->ordering(param('ordering') || undef);
                }
                elsif ($column->type eq "calc")
                {
                    $column->code(param 'code_calc');
                    $column->return_type(param 'return_type');
                    $no_alerts = param('no_alerts_calc');
                }
                elsif ($column->type eq "tree")
                {
                    $column->end_node_only(param 'end_node_only');
                }
                elsif ($column->type eq "string")
                {
                    $column->textbox(param 'textbox');
                    $column->force_regex(param 'force_regex');
                }
                elsif ($column->type eq "curval")
                {
                    $column->refers_to_instance_id(param 'refers_to_instance_id');
                    $column->filter->as_json(param 'filter');
                    my @curval_field_ids = body_parameters->get_all('curval_field_ids');
                    $column->curval_field_ids([@curval_field_ids]);
                }
                elsif ($column->type eq "autocur")
                {
                    my @curval_field_ids = body_parameters->get_all('autocur_field_ids');
                    $column->curval_field_ids([@curval_field_ids]);
                    $column->related_field_id(param 'related_field_id');
                }

                my $no_cache_update = $column->type eq 'rag' ? param('no_cache_update_rag') : param('no_cache_update_calc');
                if (process( sub { $column->write(no_alerts => $no_alerts, no_cache_update => $no_cache_update) }))
                {
                    my $msg = $col_id
                        ? qq(Your field has been updated successfully)
                        : qq(Your field has been created successfully);

                    return forwardHome( { success => $msg }, $sheet->identifier.'/layout' );
                }
            }
            $params->{column} = $column;
            push @breadcrumbs, Crumb($sheet, "/layout/".$column->id => 'edit field "'.$column->name.'"');
        }
        elsif (defined param('id'))
        {
            $params->{column} = 0; # New
            push @breadcrumbs, Crumb($sheet, "/layout/0" => 'new field');
        }
        $params->{groups}             = $site->groups;
        $params->{permissions}        = [ GADS::Type::Permissions->all ];
        $params->{permission_mapping} = GADS::Type::Permissions->permission_mapping;
        $params->{permission_inputs}  = GADS::Type::Permissions->permission_inputs;
        $params->{topics}             = [schema->resultset('Topic')->search({ instance_id => $layout->instance_id })->all];

        if (param 'saveposition')
        {
            my @position = body_parameters->get_all('position');
            if (process( sub { $layout->position(@position) }))
            {
                return forwardHome(
                    { success => "The ordering has been saved successfully" }, $sheet->identifier.'/layout' );
            }
        }

        $params->{breadcrumbs} = \@breadcrumbs;
        template 'layout' => $params;
    };

    any ['get', 'post'] => '/approval/?:id?' => require_login sub {
        my $record_id  = is_valid_id(param 'id');
        my $current_id = is_valid_id(param 'current_id');
        my $doc = $site->document;
        my $row;

        if($record_id)
        {   # If we're viewing or approving an individual record, first
            # see if it's a new record or edit of existing. This affects
            # permissions.

            $row = $doc->row(record_id => $record_id,
                sheet            => $sheet,
                include_approval => 1,
            );
        }

        my $approval_of_new = $row ? $row->approval_of_new : 0;

        if (param 'submit')
        {
            my $cur = $sheet->row(current_id => $current_id) ||
                $sheet->data->row_create(
                    current_id     => $current_id,
                    approval_id    => $record_id,
                    init_no_value  => 0,           #XXX
                    doing_approval => 1,
                );

            my $failed;
            foreach my $col ($cur->edit_columns(new => $approval_of_new, approval => 1))
            {   my $newv = param($col->field) or next;
                $col->userinput or next; # Not calculated fields

                $failed++
                    if !process( sub { $cur->field($col)->set_value($newv) });
            }

            if(!$failed)
            {   return forwardHome(
                    { success => 'Record has been successfully approved' }, $sheet->identifier.'/approval' );
            }
        }

        my $page;
        my $params = {
            page => 'approval',
        };

        if($row)
        {   # Get the record of values needing approval
            $params->{record} = $row;
            $params->{record_presentation} = $row->presentation($sheet, edit => 1, new => $approval_of_new, approval => 1);

            # Get existing values for comparison
            $params->{existing} = $sheet->row(current_id => $record->current_id)
                unless $approval_of_new;

            $page  = 'edit';
            $params->{breadcrumbs} = [
                Crumb($sheet),
                Crumb($sheet, '/approval' => 'approve records'),
                Crumb($sheet, "/approval/$id" => "approve record $id")
             ];
        }
        else
        {   $page  = 'approval';
            $params->{records}     = $sheet->data->appoval->records;
            $params->{breadcrumbs} = [
                Crumb($sheet),
                Crumb($sheet, '/approval' => 'approve records'),
            ];
        }

        template $page => $params;
    };

    any ['get', 'post'] => '/link/:id?' => require_login sub {

        my $layout = var('layout') or pass;

        my $id = param 'id';

        my $record = GADS::Record->new(
            user   => logged_in_user,
            layout => $layout,
            schema => schema,
        );

        if ($id)
        {
            $record->find_current_id($id);
        }

        if (param 'submit')
        {
            my $result;
            if ($id)
            {
                $result = process( sub { $record->write_linked_id(param 'linked_id') });
            }
            else {
                $record->initialise;
                $result = process( sub { $record->write })
                    && process( sub { $record->write_linked_id(param 'linked_id' ) });
            }
            if ($result)
            {
                return forwardHome(
                    { success => 'Record has been linked successfully' }, $sheet->identifier.'/data' );
            }
        }

        my $breadcrumbs = [Crumb($sheet)];
        if ($id)
        {
            push @$breadcrumbs, Crumb($sheet, "/link/$id" => "edit linked record $id");
        }
        else {
            push @$breadcrumbs, Crumb($sheet, '/link/' => 'add linked record');
        }
        template 'link' => {
            breadcrumbs => $breadcrumbs,
            record      => $record,
            page        => 'link',
        };
    };

    post '/edits' => require_login sub {

        my $layout = var('layout') or pass;

        my $user   = logged_in_user;

        my $records = eval { from_json param('q') };
        if ($@) {
            status 'bad_request';
            return 'Request body must contain JSON';
        }

        my $failed;
        while ( my($id, $values) = each %$records ) {
            my $record = GADS::Record->new(
                user   => $user,
                layout => $layout,
                schema => schema,
            );

            $record->find_current_id($values->{current_id});
            $layout = $record->layout; # May have changed if record from other datasheet
            if ($layout->column($values->{column})->type eq 'date')
            {
                my $to_write = $values->{from};
                unless (process sub { $record->fields->{ $values->{column} }->set_value($to_write) })
                {
                    $failed = 1;
                    next;
                }
            }
            else {
                # daterange
                my $to_write = {
                    from    => $values->{from},
                    to      => $values->{to},
                };
                # The end date as reported by the timeline will be a day later than
                # expected (it will be midnight the following day instead.
                # Therefore subtract one day from it
                unless (process sub { $record->fields->{ $values->{column} }->set_value($to_write, subtract_days_end => 1) })
                {
                    $failed = 1;
                    next;
                }
            }

            process sub { $record->write }
                or $failed = 1;
        }

        if ($failed) {
            redirect '/data'; # Errors already written to display
        }
        else {
            return forwardHome(
                { success => 'Submission has been completed successfully' }, $sheet->identifier.'/data' );
        }
    };

    any ['get', 'post'] => '/bulk/:type/?' => require_login sub {

        my $layout = var('layout') or pass;

        my $view   = current_view();
        my $type   = param 'type';

        $sheet->user_can("bulk_update")
            or forwardHome({ danger => "You do not have permission to perform bulk operations"}, $sheet->identifier.'/data');

        $type eq 'update' || $type eq 'clone'
            or error __x"Invalid bulk type: {type}", type => $type;

        # The dummy record to test for updates
        my $record = GADS::Record->new(
            user   => $user,
            layout => $layout,
        );
        $record->initialise;

        # The records to update
        my %params = (
            view                 => $view,
            search               => session('search'),
            columns              => $layout->column_ids, # Need all columns to be able to write updated records
            view_limit_extra_id  => current_view_limit_extra_id(),
        );

        my @limit_current_ids = query_parameters->get_all('id');
        $params{limit_current_ids} = \@limit_current_ids;
            if @limit_current_ids;

        my $records = GADS::Records->new(%params);

        if (param 'submit')
        {
            # See which ones to update
            my $failed_initial; my @updated;
            foreach my $col ($record->edit_columns(new => 1, bulk => $type))
            {
                my @newv = body_parameters->get_all($col->field);
                my $included = body_parameters->get('bulk_inc_'.$col->id); # Is it ticked to be included?
                report WARNING => __x"Field \"{name}\" contained a submitted value but was not checked to be included", name => $col->name
                    if join('', @newv) && !$included;
                next unless body_parameters->get('bulk_inc_'.$col->id); # Is it ticked to be included?
                my $datum = $record->field($col);
                my $success = process( sub { $datum->set_value(\@newv, bulk => 1) } );
                push @updated, $col
                    if $success;
                $failed_initial = $failed_initial || !$success;
            }
            if (!$failed_initial)
            {
                my ($success, $failures);
                while (my $record_update = $records->single)
                {
                    $record_update->remove_id
                        if $type eq 'clone';

                    my $failed;
                    foreach my $col (@updated)
                    {
                        my $newv = [ body_parameters->get_all($col->field) ];
                        last if $failed = !process( sub { $record_update->fields->{$col->id}->set_value($newv, bulk => 1) } );
                    }
                    $record_update->field($_)->re_evaluate(force => 1)
                        foreach $layout->search_columns(has_cache => 1);
                    if (!$failed)
                    {
                        # Use force_mandatory to skip "was previously blank" warnings. No
                        # records will actually be made blank, as we wouldn't write otherwise
                        if (process( sub { $record_update->write(force_mandatory => 1) } )) { $success++ } else { $failures++ };
                    }
                    else {
                        $failures++;
                    }
                }
                if (!$success && !$failures)
                {
                    notice __"No updates have been made";
                }
                elsif ($success && !$failures)
                {
                    my $msg = __xn"{_count} record was {type}d successfully", "{_count} records were {type}d successfully",
                        $success, type => $type;
                    return forwardHome(
                        { success => $msg->toString }, $sheet->identifier.'/data' );
                }
                else # Failures, back round the buoy
                {
                    my $s = __xn"{_count} record was {type}d successfully", "{_count} records were {type}d successfully",
                        ($success || 0), type => $type;
                    my $f = __xn", {_count} record failed to be {type}d", ", {_count} records failed to be {type}d",
                        ($failures || 0), type => $type;
                    mistake $s.$f;
                }
            }
        }

        my $view_name = $view ? $view->name : 'All data';

        # Get number of records in view for sanity check for user
        my $count = $records->count;
        my $count_msg = __xn", which contains 1 record.", ", which contains {_count} records.", $count;
        if ($type eq 'update')
        {
            my $notice = session('search')
                ? __x(qq(Use this page to update all records in the
                    current search results. Tick the fields whose values should be
                    updated. Fields that are not ticked will retain their existing value.
                    The current search is "{search}"), search => session('search'))
                : $params{limit_current_ids}
                ? __x(qq(Use this page to update all currently selected records.
                    Tick the fields whose values should be updated. Fields that are
                    not ticked will retain their existing value.
                    The current number of selected records is {count}.), count => scalar @{$params{limit_current_ids}})
                : __x(qq(Use this page to update all records in the
                    currently selected view. Tick the fields whose values should be
                    updated. Fields that are not ticked will retain their existing value.
                    The current view is "{view}"), view => $view_name);
            my $msg = $notice;
            $msg .= $count_msg unless $params{limit_current_ids};
            notice $msg;
        }
        else {
            my $notice = session('search')
                ? __x(qq(Use this page to bulk clone all of the records in
                    the current search results. The cloned records will be created using
                    the same existing values by default, but replaced with the values below
                    where that value is ticked. Values that are not ticked will be cloned
                    with their current value. The current search is "{search}"), search => session('search'))
                : $params{limit_current_ids}
                ? __x(qq(Use this page to bulk clone all currently selected records.
                    The cloned records will be created using
                    the same existing values by default, but replaced with the values below
                    where that value is ticked. Values that are not ticked will be cloned
                    with their current value.
                    The current number of selected records is {count}.), count => scalar @{$params{limit_current_ids}})
                : __x(qq(Use this page to bulk clone all of the records in
                    the currently selected view. The cloned records will be created using
                    the same existing values by default, but replaced with the values below
                    where that value is ticked. Values that are not ticked will be cloned
                    with their current value. The current view is "{view}"), view => $view_name);
            my $msg = $notice;
            $msg .= $count_msg unless $params{limit_current_ids};
            notice $msg;
        }

        template 'edit' => {
            view                => $view,
            record              => $record,
            record_presentation => $record->presentation($sheet, edit => 1, new => 1, bulk => $type),
            bulk_type           => $type,
            page                => 'bulk',
            breadcrumbs         => [Crumb($sheet), Crumb($sheet, "/data" => 'records'), Crumb($sheet, "/bulk/$type" => "bulk $type records")],
        };
    };

    any ['get', 'post'] => '/edit/?' => require_login sub {

        my $layout = var('layout') or pass;
        _process_edit();
    };

    any ['get', 'post'] => '/import/?' => require_any_role [qw/layout useradmin/] => sub {

        my $layout = var('layout') or pass; # XXX Need to search on this

        if (param 'clear')
        {
            rset('Import')->search({
                completed => { '!=' => undef },
            })->delete;
        }

        template 'import' => {
            imports     => [rset('Import')->search({},{ order_by => { -desc => 'me.completed' } })->all],
            page        => 'import',
            breadcrumbs => [Crumb($sheet) => Crumb($sheet, "/data" => 'records') => Crumb($sheet, "/import" => 'imports')],
        };
    };

    get '/import/rows/:import_id' => require_any_role [qw/layout useradmin/] => sub {

        my $layout = var('layout') or pass; # XXX Need to search on this

        my $import_id = param 'import_id';
        rset('Import')->find($import_id)
            or error __"Requested import not found";

        my $rows = rset('ImportRow')->search({
            import_id => param('import_id'),
        },{
            order_by => {
                -asc => 'me.id',
            }
        });

        template 'import/rows' => {
            import_id   => param('import_id'),
            rows        => $rows,
            page        => 'import',
            breadcrumbs => [Crumb($sheet) => Crumb($sheet, "/data" => 'records')
                => Crumb($sheet, "/import" => 'imports'), Crumb($sheet, "/import/rows/$import_id" => "import ID $import_id") ],
        };
    };

    any ['get', 'post'] => '/import/data/?' => require_login sub {

        my $sheet = var('layout') or pass;

        my $user  = $::session->user;
        $sheet->user_can("layout")
            or forwardHome({ danger => "You do not have permission to import data"}, '');

        if (param 'submit')
        {
            if (my $upload = upload('file'))
            {
                my %options = map { $_ => 1 } body_parameters->get_all('import_options');
                $options{no_change_unless_blank} = 'skip_new' if $options{no_change_unless_blank};
                $options{update_unique} = param('update_unique') if param('update_unique');
                $options{skip_existing_unique} = param('skip_existing_unique') if param('skip_existing_unique');
                my $import = GADS::Import->new(
                    file     => $upload->tempname,
                    layout   => var('layout'),
                    %options,
                );

                if (process sub { $import->process })
                {
                    return forwardHome(
                        { success => "The file import process has been started and can be monitored using the Import Status below" }, $sheet->identifier.'/import' );
                }
            }
            else {
                report({is_fatal => 0}, ERROR => 'Please select a file to upload');
            }
        }

        template 'import/data' => {
            layout      => var('layout'),
            page        => 'import',
            breadcrumbs => [Crumb($sheet) => Crumb($sheet, "/data" => 'records')
                => Crumb($sheet, "/import" => 'imports'), Crumb($sheet, "/import/data" => 'new import') ],
        };
    };

    any ['get', 'post'] => '/graphs/?' => require_login sub {

        my $layout = var('layout') or pass;
        my $user   = logged_in_user;

        if (param 'graphsubmit')
        {
            if (process( sub { $user->set_graphs($layout, [body_parameters->get_all('graphs')]) }))
            {
                return forwardHome(
                    { success => "The selected graphs have been updated" }, $sheet->identifier.'/data' );
            }
        }

        my $graphs = GADS::Graphs->new(
            current_user => $user,
            layout       => $layout,
        );

        template 'graphs' => {
            graphs      => [ $graphs->all ],
            page        => 'graphs',
            breadcrumbs => [Crumb($sheet) => Crumb($sheet, '/data' => 'records') => Crumb($sheet, '/graph' => 'graphs')],
        };
    };

    get '/match/user/' => require_login sub {

        my $layout = var('layout') or pass;
        $sheet->user_can("layout") or error "No access to search for users";

        my $query = param('q');
        content_type 'application/json';
        to_json [ rset('User')->match($query) ];
    };

    get '/match/layout/:layout_id' => require_login sub {

        my $layout = var('layout') or pass;
        my $query = param('q');
        my $with_id = param('with_id');
        my $layout_id = param('layout_id');

        my $column = $layout->column($layout_id, permission => 'read');

        content_type 'application/json';
        to_json [ $column->values_beginning_with($query, with_id => $with_id) ];
    };

};

sub reset_text {
    my ($dsl, %options) = @_;
    my $name = $site->name || config->{gads}->{name} || 'Linkspace';
    my $url  = request->base . "resetpw/$options{code}";
    my $body = <<__BODY;
A request to reset your $name password has been received. Please
click on the following link to set and retrieve a new password:

$url
__BODY

    my $html = <<__HTML;
<p>A request to reset your $name password has been received. Please
click on the following link to set and retrieve a new password:</p>

<p><a href="$url">$url<a></p>
__HTML

    return (
        from    => config->{gads}->{email_from},
        subject => 'Password reset request',
        plain   => wrap('', '', $body),
        html    => $html,
    )
}

sub current_view {
    my $view_id = session('persistent')->{view}{$sheet->id};
    $sheet->views->view($view_id) || $sheet->views->view_default;
};

sub current_view_limit_extra()
{   my $extra_id = session('persistent')->{view_limit_extra}{$sheet->id}
       ||= $sheet->default_view_limit_extra_id;

    $sheet->view($extra_id);  # includes check existence
}

sub current_view_limit_extra_id()
{   my $view  = current_view_limit_extra();
    $view ? $view->id : undef;
}

sub forwardHome {
    my ($message, $page, %options) = @_;

    if ($message)
    {
        my ($type) = keys %$message;
        my $lroptions = {};
        # Check for option to only display to user (e.g. passwords)
        $lroptions->{to} = 'error_handler' if $options{user_only};

        if ($type eq 'danger')
        {
            $lroptions->{is_fatal} = 0;
            report $lroptions, ERROR => $message->{$type};
        }
        elsif ($type eq 'notice') {
            report $lroptions, NOTICE => $message->{$type};
        }
        else {
            report $lroptions, NOTICE => $message->{$type}, _class => 'success';
        }
    }
    $page ||= '';
    redirect "/$page";
}

sub _random_pw
{   $password_generator->xkcd( words => 3, digits => 2 );
}

sub _page_as_mech
{   my ($template, $params, %options) = @_;
    $params->{scheme}       = 'http';
    my $public              = path(setting('appdir'), 'public');
    $params->{base}         = "file://$public/";
    $params->{page_as_mech} = 1;
    $params->{zoom}         = (int $options{zoom} || 100) / 100;
    my $timeline_html       = template $template, $params;
    my ($fh, $filename)     = tempfile(SUFFIX => '.html');
    print $fh $timeline_html;
    close $fh;
    my $mech = WWW::Mechanize::PhantomJS->new;
    if ($options{pdf})
    {
        $mech->eval_in_phantomjs("
            this.paperSize = {
                format: 'A3',
                orientation: 'landscape',
                margin: '0.5cm'
            };
        ");
    }
    elsif ($options{width} && $options{height}) {
        $mech->eval_in_phantomjs("
            this.viewportSize = {
                width: $options{width},
                height: $options{height},
            };
        ");
    }
    $mech->get_local($filename);
    # Sometimes the timeline does not render properly (it is completely blank).
    # This only seems to happen in certain views, but adding a brief sleep
    # seems to fix ti - maybe things are going out of scope before PhantomJS has
    # finished its work?
    sleep 1;
    unlink $filename;
    return $mech;
}

sub _data_graph
{   my $id = shift;

    my $records = GADS::RecordsGraph->new(
        search              => session('search'),
        view_limit_extra_id => current_view_limit_extra_id(),
        rewind              => session('rewind'),
    );

    GADS::Graph::Data->new(
        id      => $id,
        records => $records,
        view    => current_view(),
    );
}

sub _process_edit
{   my $id = shift;

    my %params = (
        user                 => $user,
        # Need to get all fields of curvals in case any are drafts for editing
        # (otherwise all field values will not be passed to form)
        curcommon_all_fields => 1,
    );

#XXX layout is known by $sheet->layout
    $params{layout} = var('layout') if var('layout'); # Used when creating a new record

#XXX no: do not create an empty record first
    my $record = GADS::Record->new(%params);

    if (my $delete_id = param 'delete')
    {
        $sheet->user_can("delete")
            or error __"You do not have permission to delete records";

#XXX    $sheet->data->delete_current_record;
        if (process( sub { $record->delete_current($sheet) }))
        {
            return forwardHome(
                { success => 'Record has been deleted successfully' }, $record->layout->identifier.'/data' );
        }
    }

    if (param 'delete_draft')
    {
        $sheet->user_can("delete")
            or error __"You do not have permission to delete records";

#XXX    $sheet->data->delete_drafts
        if (process( sub { $record->delete_user_drafts($sheet) }))
        {
            return forwardHome(
                { success => 'Draft has been deleted successfully' }, $sheet->identifier.'/data' );
        }
    }

    my $layout;

    if ($id)
    {
        my $include_draft = defined(param 'include_draft');
        $record->find_current_id($id, include_draft => $include_draft);
        $layout = $record->layout;
        var 'layout' => $layout;
    }
    else {
        # New record
        $layout = var 'layout'; # undef for existing record
    }

    my $child = param('child') || $record->parent_id;

    my $modal = is_valid_id(param 'modal');
    my $oi    = is_valid_id(param 'oi');

    $record->initialise unless $id;

    my $validate_only = defined(param 'validate');
    if(param('submit') || param('draft') || $modal || $validate_only)
    {
        my $failed;

        !$child || $id || $sheet->user_can('create_child')
            or error __"You do not have permission to create a child record";

        $record->parent_id($child);

        # We actually only need the write columns for this. The read-only
        # columns can be ignored, but if we do write them, an error will be
        # thrown to the user if they've been changed. This is better than
        # just silently ignoring them, IMHO.
        my @display_on_fields;
        my @validation_errors;
        foreach my $col ($record->edit_columns(new => !$id))
        {
            my $newv;
            if ($modal)
            {   next unless defined query_parameters->get($col->field);
                $newv = [ query_parameters->get_all($col->field) ];
            }
            else
            {   next unless defined body_parameters->get($col->field);
                $newv = [ body_parameters->get_all($col->field) ];
            }

            $col->userinput && defined $newv # Not calculated fields
                or next;

            # No need to do anything if the file's just been uploaded
            my $datum = $record->field($col);
            if($do_validate)
            {
                try { $datum->set_value($newv) };
                if (my $e = $@->wasFatal)
                { push @validation_errors, $e->message;
                }
            }
            else
            {   $failed = !process( sub { $datum->set_value($newv) } ) || $failed;
            }
        }

        # Call this now, to write and blank out any non-displayed values,
        $record->set_blank_dependents;

        if($validate_only)
        {
            try { $record->write(dry_run => 1) };
            if (my $e = $@->died) # XXX This should be ->wasFatal() but it returns the wrong message
            {
                push @validation_errors, $e;
            }
            my $message = join '; ', @validation_errors;
            content_type 'application/json; charset="utf-8"';
            return encode_json ({
                error   => $message ? 1 : 0,
                message => $message,
                values  => +{ map +($_->field => $record->field($_)->as_string), @{$layout->columns},
            });
        }
        elsif ($modal)
        {
            # Do nothing, just a live edit, no write required
        }
        elsif (param 'draft')
        {
            if (process sub { $record->write(draft => 1, submission_token => param('submission_token')) })
            {
                return forwardHome(
                    { success => 'Draft has been saved successfully'}, $sheet->identifier.'/data' );
            }

            return forwardHome(undef, $sheet->identifier.'/data')
                if $record->already_submitted_error;
        }
        elsif (!$failed)
        {
            if (process( sub { $record->write(submission_token => param('submission_token')) }))
            {   my $current_id = $record->current_id;
                my $forward = !$id && $layout->forward_record_after_create
                  ? "record/$current_id"
                  : $sheet->identifier.'/data';

                return forwardHome({ success =>
                    "Submission has been completed successfully for record ID $current_id" }, $forward );
            }

            return forwardHome(undef, $sheet->identifier.'/data')
                if $record->already_submitted_error;
        }
    }
    elsif($id) {
        # Do nothing, record already loaded
    }
    elsif(my $from = is_valid_id(param 'from'))
    {   my $toclone = $sheet->data->row(current_id => $from,
           curcommon_all_fields => 1);
        $record = $toclone->clone;
    }
    else {
        $record->load_remembered_values;
    }

    # Clear all fields which we may write but not read.
    $record->field($_)->set_value("")
        for grep ! $_->user_can('read'),
               $sheet->layout->search_columns(user_can_write => 1);

    my $child_rec = $child && $sheet->user_can('create_child')
        ? is_valid_id(param 'child')
        : $record->parent_id;

    notice __"Values entered on this page will have their own value in the child "
      . "record. All other values will be inherited from the parent."
        if $child_rec;

    my @breadcrumbs = (Crumb($sheet), Crumb($sheet, '/data' => 'records'));
    push @breadcrumbs, $id
      ? Crumb("/edit/$id" => "edit record $id")
      : Crumb($sheet, '/edit/' => 'new record');

    my %params = (
        record              => $record,
        modal               => $modal,
        page                => 'edit',
        child               => $child_rec,
        layout_edit         => $layout,
        clone               => param('from'),
        submission_token    => !$modal && $record->create_submission_token,
        breadcrumbs         => \@breadcrumbs,
        record_presentation => $record->presentation($sheet, edit => 1, new => !$id, child => $child),
    );

    $params{modal_field_ids} = encode_json $sheet->layout->column($modal)
        ->curval_field_ids
        if $modal;

    my $options = $modal ? { layout => undef } : {};

    template edit => \%params, $options;
}

true;
