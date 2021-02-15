## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package GADS::API;

use Crypt::SaltedHash;
use MIME::Base64 qw/decode_base64/;
use Net::OAuth2::AuthorizationServer::PasswordGrant;
use Session::Token;

use Dancer2 appname => 'GADS';
use Dancer2::Plugin::Auth::Extensible;
use Dancer2::Plugin::DBIC;
use Dancer2::Plugin::LogReport 'linkspace';

# Special error handler for JSON requests (as used in API)
fatal_handler sub {
    my ($dsl, $msg, $reason) = @_;
    return unless $dsl && $dsl->app->request && $dsl->app->request->uri =~ m!^/([0-9a-z]+/)?api/!i;
    status $reason eq 'PANIC' ? 'Internal Server Error' : 'Bad Request';
    $dsl->send_as(JSON => {
        is_error => \1,
        message  => $msg->toString },
    { content_type => 'application/json; charset=UTF-8' });
};

sub _verify_user_password
{   my %args = @_;

    my $client = $::db->get_record(Oauthclient => {
        client_id     => $args{client_id},
        client_secret => $args{client_secret},
    });
        or return (0, 'unauthorized_client');

    my $user = $::session->site->users->user_by_name($args{username});
    $user && Crypt::SaltedHash->validate($user->password, $args{password})
        and return ($client->id, undef, undef, $user->id);

    (0, 'access_denied');
};

sub _store_access_token
{   my %args = @_;

    if (my $old_refresh_token = $args{old_refresh_token})
    {
        my $prev_rt = $::db->resultset('Oauthtoken')->refresh_token($old_refresh_token);
        my $prev_at = $::db->resultset('Oauthtoken')->access_token($prev_rt->related_token);
        $prev_at->delete;
    }

    # if the client has en existing refresh token we need to revoke it
    $::db->delete(Oauthtoken => {
        type           => 'refresh',
        oauthclient_id => $args{client_id},
        user_id        => $args{user_id},
    });

    my $access_token  = $args{access_token};
    my $refresh_token = $args{refresh_token};

    $::db->create(Oauthtoken => {
        type           => 'access',
        token          => $access_token,
        expires        => time + $args{expires_in},
        related_token  => $refresh_token,
        oauthclient_id => $args{client_id},
        user_id        => $args{user_id},
    });

    $::db->create(Oauthtoken => {
        type           => 'refresh',
        token          => $refresh_token,
        related_token  => $access_token,
        oauthclient_id => $args{client_id},
        user_id        => $args{user_id},
    });
};

sub _verify_access_token
{   my %args = @_;

    my $access_token = $args{access_token};

    my $rt = $::db->resultset('Oauthtoken')->refresh_token($access_token);
    return $rt
        if $args{is_refresh_token} && $rt;

    if(my $at = $::db->resultset('Oauthtoken')->access_token($access_token))
    {   $at->expires <= time or return $at;
        $at->delete;
    }
    (0, 'invalid_grant');
};

my $Grant = Net::OAuth2::AuthorizationServer::PasswordGrant->new(
    verify_user_password_cb => \&_verify_user_password,
    store_access_token_cb   => \&_store_access_token,
    verify_access_token_cb  => \&verify_access_token,
);

hook before => sub {
    my ($client, $error) = $Grant->verify_token_and_scope(
        auth_header => scalar request->header('authorization'),
    );
    var api_user => $client->user if $client;
};

sub require_api_user {
    my $route = shift;
    sub {
        return $route->() if var('api_user');
        status('Forbidden');
        error "Authentication needed to access this resource";
    };
};

sub _update_record
{   my ($record, $request) = @_;
    foreach my $field (keys %$request)
    {   my $col = $record->layout->column_by_name_short($field)
            or error __x"Column not found: {name}", name => $field;
        $record->fields->{$col->id}->set_value($request->{$field});
    }
    $record->write; # borks on error
};

# Create new record
post '/api/record/:sheet' => require_api_user sub {
    my $sheet = $::session->site(param 'sheet');
    my $data  = decode_json request->body;

    error "Invalid field: id; Use the PUT method to update an existing record"
        if exists $request->{id};

    $sheet->content->create_record(datums => $data);

    status 'Created';
    header 'Location' => request->base.'record/'.$record->current_id;

    return;
};

# Edit existing record or new record with non-Linkspace index ID
put '/api/record/:sheet/:id' => require_api_user sub {

    my $sheet = $::session->site(param 'sheet');
    my $id    = param 'id';

    my $request = decode_json request->body;
    my $row;

    if(my $api_index = $sheet->api_index_layout)
    {   $row = $sheet->content->find_unique($api_index, $id);
        $row || $request->{$api_index->name_short} = $id; #XXX row = undef
    }
    else
    {   $record_to_update = $sheet->content->find_current_id($id);
    }

    $row->columns_update($request);

    status 'No Content';
    # Use supplied ID for return - will either have been created as that or
    # will have borked early with error and not got here
    header 'Location' => request->base."record/$id";

    return;
};

# Get existing record
get '/api/record/:sheet/:id' => require_api_user sub {
    $::session->site->sheet(param 'sheet');
    my $id        = param 'id';

    my $row;
    if(my $api_index = $layout->api_index_layout)
    {   $row = $sheet->content->find_unique($api_index, $id)
            or error __x"Record ID {id} not found", id => $id; # XXX Would be nice to reuse GADS::Record error
        $row = $sheet->content->find_current_id($record->current_id);
    }
    else
    {   $row = $sheet->content->find_current_id($id);
    }

    content_type 'application/json; charset=UTF-8';
    return $record->as_json;
};

get '/clientcredentials/?' => require_any_role [qw/superadmin/] => sub {
    my $credentials = $::db->get_record('Oauthclient') ||
        $::db->create(Oauthclient => {
            client_id     => Session::Token->new(length => 12)->get,
            client_secret => Session::Token->new(length => 12)->get,
        });

    return template 'api/clientcredentials' => {
        credentials => $credentials,
    };
};

post '/api/token' => sub {

    my ($client_id_submit, $client_secret);

    # RFC6749 says try auth header first, then fall back to body params
    if (my $auth = request->header('authorization'))
    {
        if (my ($encoded) = split 'Basic ', $auth)
        {   if (my $decoded = decode_base64 $encoded)
            {   ($client_id_submit, $client_secret) = split ':', $decoded;
            }
        }
    }
    else
    {   $client_id_submit = param 'client_id';
        $client_secret    = param 'client_secret';
    }

    my ($client_id, $error, $scopes, $user_id, $json_response, $old_refresh_token);

    my $grant_type = param 'grant_type';

    if($grant_type eq 'password')
    {
        ($client_id, $error, $scopes, $user_id) = $Grant->verify_user_password(
            client_id     => $client_id_submit,
            client_secret => $client_secret,
            username      => param('username'),
            password      => param('password'),
        );
    }
    elsif($grant_type eq 'refresh_token')
    {
        my $refresh_token = param 'refresh_token';
        ($client_id, $error, $scopes, $user_id) = $Grant->verify_token_and_scope(
            refresh_token => $refresh_token,
            auth_header   => request->header('authorization'),
        );
        $old_refresh_token = $refresh_token;
    }
    else
    {   $json_response = {
            error             => 'invalid_request',
            error_description => "Invalid grant type: ".param('grant_type'),
        };
    }

    if($client_id)
    {
        my $access_token = $Grant->token(
            client_id  => param 'client_id',
            type       => 'access',
        );

        my $refresh_token = $Grant->token(
            client_id  => param 'client_id',
            type       => 'refresh', # one of: access, refresh
        );

        my $expires_in = $Grant->access_token_ttl;

        $Grant->store_access_token(
          user_id           => $user_id,
          client_id         => $client_id,
          access_token      => $access_token,
          expires_in        => $expires_in,
          refresh_token     => $refresh_token,
          old_refresh_token => $old_refresh_token,
        );

        $json_response = {
            access_token  => $access_token,
            token_type    => 'Bearer',
            expires_in    => $expires_in,
            refresh_token => $refresh_token,
        };
    }
    elsif(!$json_response)
    {   $json_response = +{ error => $error };
    }

    header "Cache-Control" => 'no-store';
    header "Pragma"        => 'no-cache';
    content_type 'application/json;charset=UTF-8';

    return encode_json $json_response;
};

prefix '/:sheet_name' => sub {

    get '/api/field/values/:id' => require_login sub {
        my $sheet_name = route_parameters->get('sheet_name');
        my $sheet  = $::session->site->sheet($sheet_name);
        my $col_id = route_parameters->get('id');
        my $curval = $sheet->layout->column($col_id);

        try {
            my @datums;
            my $required_columns = $curval->subvals_input_required;
            foreach my $col (@$required_columns)
            {   my @vals = grep defined && length,
                    query_parameters->get_all($col->field_name);
                push @datums, $column->datum_create($col, \@vals, validate => 1);
            }

            $sheet->content->row_create(cells => \@datums,
                missing_not_fatal => 1,
                submitted_fields  => $required_columns,
            );
        } # Missing values are reporting as non-fatal errors, and would therefore
          # not be caught by the try block and would be reported as normal (including
          # to the message session). We need to hide these and report them now.
          hide => 'ERROR';

        $@->reportFatal; # Report any unexpected fatal messages from the try block

        if (my @excps = grep $_->reason eq 'ERROR', $@->exceptions)
        {   my $msg = "The following fields need to be completed first: "
                .join ', ', map $_->message->toString, @excps;

            return encode_json { error => 1, message => $msg };
        }

        return encode_json {
            error   => 0,
            records => [
                map +{ id => $_->{id}, label => $_->{value} }, @{$curval->filtered_values}
            ]
        };
    };
    post '/api/dashboard/:dashboard_id/widget'         => require_login \&_post_dashboard_widget;
    put '/api/dashboard/:dashboard_id/dashboard/:id'   => require_login \&_put_dashboard_dashboard;
    get '/api/dashboard/:dashboard_id/widget/:id'      => require_login \&_get_dashboard_widget;
    get '/api/dashboard/:dashboard_id/widget/:id/edit' => require_login \&_get_dashboard_widget_edit;
    put '/api/dashboard/:dashboard_id/widget/:id/edit' => require_login \&_put_dashboard_widget_edit;
    del '/api/dashboard/:dashboard_id/widget/:id'      => require_login \&_del_dashboard_widget;
};

# Same as prefix routes above, but without layout identifier - these are for
# site dashboard configuration
#XXX above are useless: dashboard_id is linked to the sheet.

post '/api/dashboard/:dashboard_id/widget'         => require_login \&_post_dashboard_widget;
put '/api/dashboard/:dashboard_id/dashboard/:id'   => require_login \&_put_dashboard_dashboard;
get '/api/dashboard/:dashboard_id/widget/:id'      => require_login \&_get_dashboard_widget;
get '/api/dashboard/:dashboard_id/widget/:id/edit' => require_login \&_get_dashboard_widget_edit;
put '/api/dashboard/:dashboard_id/widget/:id/edit' => require_login \&_put_dashboard_widget_edit;
del '/api/dashboard/:dashboard_id/widget/:id'      => require_login \&_del_dashboard_widget;

sub _dashboard(%)
{   my %args    = @_;
    my $dash_id = route_parameters->get('dashboard_id');

    my $dashboard = $::session->site->dashboard($dash_id);
    unless($dashboard)
    {   status 404;
        error __x"Dashboard {id} not found", id => $dash_id;
    }

    my $access = $args{access} || 'read';
    if($access eq 'write' && ! $dashboard->can_write($user))
    {   status 403;
        error __x"User does not have write access to dashboard ID {id}", id => $id;
    }

    $dashboard;
}

sub _widget(;$)
{   my $dashboard = shift || _dashboard;
    my $grid_id   = route_parameters->get('id');
    my $widget    = $dashboard->widget_by_grid_id($grid_id);
    if(!$widget)
    {   status 404;
        error __x"Widget ID {id} not found", id => $grid_id;
    }
    $widget;
}


sub _post_dashboard_widget {
    my $layout    = shift;
    my $dashboard = _dashboard access => 'write';
    my $type      = query_parameters->get('type');

    my $content   = $type eq 'notice'
      ? "This is a new notice widget - click edit to update the contents" : undef;

    my $widget    = $dashboard->widget_create({
        type      => $type,
        content   => $content,
    });

    _success($widget->grid_id);
}

sub _put_dashboard_dashboard {
    my $layout = shift;
    return  _update_dashboard($layout, $user);
}

sub _get_dashboard_widget { _widget->html }

sub _get_dashboard_widget_edit
{   my $dashboard = _dashboard access => write;
    my $widget    = _widget $dashboard;

    my $params    = {
        widget        => $widget,
        tl_options    => $widget->tl_options,
        globe_options => $widget->globe_options,
    };

    my $sheet = $dashboard->sheet;

    if($sheet && $widget->type ne 'notice')
    {   $params->{user_views}   = $sheet->views->user_views;
        $params->{columns_read} = [ $sheet->layout->columns_search(user_can_read => 1) ];
    }
    elsif($sheet && $widget->type eq 'graph')
    {   $params->{graphs}       = $sheet->graphs->user_graphs;
    }

    my $content = template 'widget' => $params, {
        layout => undef, # Do not render page header, footer etc
    };

    # Keep consistent with return type generated on error
    encode_json {
        is_error => 0,
        content  => $content,
    };
}

sub _put_dashboard_widget_edit
{   my $dashboard = _dashboard access => 'write';
    my $widget    = _widget $dashboard;

    my %update = (
        title   => query_parameters->get('title'),
        view_id => query_parameters->get('view_id'),
    );

    $update{is_static} = query_parameters->get('static')
        if $dashboard->is_shared;

    if($widget->type eq 'notice')
    {   $update{content} = query_parameters->get('content');
    }
    elsif($widget->type eq 'graph')
    {   $update{graph_id} = query_parameters->get('graph_id');
    }
    elsif ($widget->type eq 'table')
    {   $update{rows}     = query_parameters->get('rows');
    }
    elsif ($widget->type eq 'timeline')
    {   $update{tl_options} = +{
            label   => query_parameters->get('tl_label'),
            group   => query_parameters->get('tl_group'),
            color   => query_parameters->get('tl_color'),
            overlay => query_parameters->get('tl_overlay'),
        };
    }
    elsif($widget->type eq 'globe')
    {   $update{globe_options} = encode_json +{
            label   => query_parameters->get('globe_label'),
            group   => query_parameters->get('globe_group'),
            color   => query_parameters->get('globe_color'),
        };
    }

    $widget->widget_update(\%update);
    _success("Widget updated successfully");
}

sub _del_dashboard_widget
{   my $dashboard = _dashboard access => 'write';
    $dashboard->widget_delete(_widget $dashboard);
    _success("Widget deleted successfully");
}

sub _update_dashboard
{   my ($layout, $user) = @_;
    my $dashboard   = _dashboard access => write;
    my $widget_data = decode_json request->body;

    foreach my $d (@$widget_data)
    {   # Static widgets added to personal dashboards will be passed in, but we
        # don't want to include these in the personal dashboard as they are
        # added anyway on dashboard render
        next if $d->{static} && !$dashboard->is_shared;

        # Do not update widget static status, as this does not seem to be
        # passed in
        my %update;
        @update{ qw/grid_id h w x y/ } = @d{ qw/i h w x y/ };

        if(my $widget = $dashboard->widget_by_grid_id($update->{grid_id}))
        {   $dashboard->widget_update($widget, \%update);
        }
        else
        {   $dashboard->widget_create(\%update);
        }
    }

    _success("Dashboard updated successfully");
}

sub _success
{   my $msg = shift;
    content_type 'application/json;charset=UTF-8';
    encode_json {
        is_error => 0,
        message  => $msg,
    };
}
1;
