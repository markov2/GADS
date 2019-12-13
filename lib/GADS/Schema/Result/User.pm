use utf8;
package GADS::Schema::Result::User;

=head1 NAME

GADS::Schema::Result::User

=cut

use strict;
use warnings;

use Log::Report 'linkspace';
use Moo;
use DateTime;

use GADS::Email;
use Linkspace::Audit;

extends 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<user>

=cut

__PACKAGE__->table("user");

=head1 ACCESSORS

=head2 id

  data_type: 'bigint'
  is_auto_increment: 1
  is_nullable: 0

=head2 site_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 firstname

  data_type: 'varchar'
  is_nullable: 1
  size: 128

=head2 surname

  data_type: 'varchar'
  is_nullable: 1
  size: 128

=head2 email

  data_type: 'text'
  is_nullable: 1

=head2 username

  data_type: 'text'
  is_nullable: 1

=head2 title

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 organisation

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 department_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 team_id

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 1

=head2 freetext1

  data_type: 'text'
  is_nullable: 1

=head2 freetext2

  data_type: 'text'
  is_nullable: 1

=head2 password

  data_type: 'varchar'
  is_nullable: 1
  size: 128

=head2 pwchanged

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 resetpw

  data_type: 'varchar'
  is_nullable: 1
  size: 32

=head2 deleted

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 lastlogin

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 lastfail

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 failcount

  data_type: 'integer'
  is_nullable: 1

=head2 lastrecord

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 lastview

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 session_settings

  data_type: 'text'
  is_nullable: 1

=head2 value

  data_type: 'text'
  is_nullable: 1

=head2 account_request

  data_type: 'smallint'
  default_value: 0
  is_nullable: 1

=head2 account_request_notes

  data_type: 'text'
  is_nullable: 1

=head2 aup_accepted

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 limit_to_view

  data_type: 'bigint'
  is_foreign_key: 1
  is_nullable: 1

=head2 stylesheet

  data_type: 'text'
  is_nullable: 1

=head2 created

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 1

=head2 debug_login

  data_type: 'smallint'
  default_value: 0
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "bigint", is_auto_increment => 1, is_nullable => 0 },
  "site_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "firstname",
  { data_type => "varchar", is_nullable => 1, size => 128 },
  "surname",
  { data_type => "varchar", is_nullable => 1, size => 128 },
  "email",
  { data_type => "text", is_nullable => 1 },
  "username",
  { data_type => "text", is_nullable => 1 },
  "title",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "organisation",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "department_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "team_id",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 1 },
  "freetext1",
  { data_type => "text", is_nullable => 1 },
  "freetext2",
  { data_type => "text", is_nullable => 1 },
  "password",
  { data_type => "varchar", is_nullable => 1, size => 128 },
  "pwchanged",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "resetpw",
  { data_type => "varchar", is_nullable => 1, size => 32 },
  "deleted",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "lastlogin",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "lastfail",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "failcount",
  { data_type => "integer", default_value => 0, is_nullable => 0 },
  "lastrecord",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "lastview",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "session_settings",
  { data_type => "text", is_nullable => 1 },
  "value",
  { data_type => "text", is_nullable => 1 },
  "account_request",
  { data_type => "smallint", default_value => 0, is_nullable => 1 },
  "account_request_notes",
  { data_type => "text", is_nullable => 1 },
  "aup_accepted",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "limit_to_view",
  { data_type => "bigint", is_foreign_key => 1, is_nullable => 1 },
  "stylesheet",
  { data_type => "text", is_nullable => 1 },
  "created",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "debug_login",
  { data_type => "smallint", default_value => 0, is_nullable => 1 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");

=head1 RELATIONS

=head2 alerts

Type: has_many

Related object: L<GADS::Schema::Result::Alert>

=cut

__PACKAGE__->has_many(
  "alerts",
  "GADS::Schema::Result::Alert",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 audits

Type: has_many

Related object: L<GADS::Schema::Result::Audit>

=cut

__PACKAGE__->has_many(
  "audits",
  "GADS::Schema::Result::Audit",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "audits_last_month",
  "GADS::Schema::Result::Audit",
  sub {
      my $args    = shift;
      my $foreign = $args->{foreign_alias};
      my $month   = DateTime->now->subtract(months => 1);
      +{
          "$foreign.user_id"  => { -ident => "$args->{self_alias}.id" },
          "$foreign.datetime" => { '>'    => $::db->format_date($month) },
      };
  }
);

=head2 lastrecord

Type: belongs_to

Related object: L<GADS::Schema::Result::Record>

=cut

__PACKAGE__->belongs_to(
  "lastrecord",
  "GADS::Schema::Result::Record",
  { id => "lastrecord" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 lastview

Type: belongs_to

Related object: L<GADS::Schema::Result::View>

=cut

__PACKAGE__->belongs_to(
  "lastview",
  "GADS::Schema::Result::View",
  { id => "lastview" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 limit_to_view

Type: belongs_to

Related object: L<GADS::Schema::Result::View>

=cut

__PACKAGE__->belongs_to(
  "limit_to_view",
  "GADS::Schema::Result::View",
  { id => "limit_to_view" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 organisation

Type: belongs_to

Related object: L<GADS::Schema::Result::Organisation>

=cut

__PACKAGE__->belongs_to(
  "organisation",
  "GADS::Schema::Result::Organisation",
  { id => "organisation" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 department

Type: belongs_to

Related object: L<GADS::Schema::Result::Department>

=cut

__PACKAGE__->belongs_to(
  "department",
  "GADS::Schema::Result::Department",
  { id => "department_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 team

Type: belongs_to

Related object: L<GADS::Schema::Result::Team>

=cut

__PACKAGE__->belongs_to(
  "team",
  "GADS::Schema::Result::Team",
  { id => "team_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 site

Type: belongs_to

Related object: L<GADS::Schema::Result::Site>

=cut

__PACKAGE__->belongs_to(
  "site",
  "GADS::Schema::Result::Site",
  { id => "site_id" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 people

Type: has_many

Related object: L<GADS::Schema::Result::Person>

=cut

__PACKAGE__->has_many(
  "people",
  "GADS::Schema::Result::Person",
  { "foreign.value" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 view_limits

Type: has_many

Related object: L<GADS::Schema::Result::ViewLimit>

=cut

__PACKAGE__->has_many(
  "view_limits",
  "GADS::Schema::Result::ViewLimit",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 record_approvedbies

Type: has_many

Related object: L<GADS::Schema::Result::Record>

=cut

__PACKAGE__->has_many(
  "record_approvedbies",
  "GADS::Schema::Result::Record",
  { "foreign.approvedby" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 record_createdbies

Type: has_many

Related object: L<GADS::Schema::Result::Record>

=cut

__PACKAGE__->has_many(
  "record_createdbies",
  "GADS::Schema::Result::Record",
  { "foreign.createdby" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 imports

Type: has_many

Related object: L<GADS::Schema::Result::Import>

=cut

__PACKAGE__->has_many(
  "imports",
  "GADS::Schema::Result::Import",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 title

Type: belongs_to

Related object: L<GADS::Schema::Result::Title>

=cut

__PACKAGE__->belongs_to(
  "title",
  "GADS::Schema::Result::Title",
  { id => "title" },
  {
    is_deferrable => 1,
    join_type     => "LEFT",
    on_delete     => "NO ACTION",
    on_update     => "NO ACTION",
  },
);

=head2 user_graphs

Type: has_many

Related object: L<GADS::Schema::Result::UserGraph>

=cut

__PACKAGE__->has_many(
  "user_graphs",
  "GADS::Schema::Result::UserGraph",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_groups

Type: has_many

Related object: L<GADS::Schema::Result::UserGroup>

=cut

__PACKAGE__->has_many(
  "user_groups",
  "GADS::Schema::Result::UserGroup",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);


=head2 user_lastrecords

Type: has_many

Related object: L<GADS::Schema::Result::UserLastrecord>

=cut

__PACKAGE__->has_many(
  "user_lastrecords",
  "GADS::Schema::Result::UserLastrecord",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 user_permissions

Type: has_many

Related object: L<GADS::Schema::Result::UserPermission>

=cut

__PACKAGE__->has_many(
  "user_permissions",
  "GADS::Schema::Result::UserPermission",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

=head2 views

Type: has_many

Related object: L<GADS::Schema::Result::View>

=cut

__PACKAGE__->has_many(
  "views",
  "GADS::Schema::Result::View",
  { "foreign.user_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

sub sqlt_deploy_hook {
    my ($self, $sqlt_table) = @_;
    $sqlt_table->add_index(name => 'user_idx_value', fields => [ { name => 'value', size => 64 } ]);
    $sqlt_table->add_index(name => 'user_idx_email', fields => [ { name => 'email', size => 64 } ]);
    $sqlt_table->add_index(name => 'user_idx_username', fields => [ { name => 'username', size => 64 } ]);
}

# Used to check if a user has a group
has has_group => (
    is => 'lazy',
);

sub _build_has_group
{   my $self = shift;
    +{
        map { $_->group_id => 1 } $self->user_groups
    };
}

# Used to check if a user has a permission
has permission => (
    is      => 'lazy',
    clearer => 1,
);

sub _build_permission
{   my $self = shift;
    my %all = map { $_->id => $_->name } $self->result_source->schema->resultset('Permission')->all;
    +{
        map { $all{$_->permission_id} => 1 } $self->user_permissions
    };
}

sub update_user
{   my ($self, %params) = @_;

    my $guard = $self->result_source->schema->txn_scope_guard;

    my $current_user = delete $params{current_user}
        or panic "Current user not defined on user update";

    length $params{firstname} <= 128
        or error __"Forename must be less than 128 characters";
    length $params{surname} <= 128
        or error __"Surname must be less than 128 characters";
    !defined $params{organisation} || $params{organisation} =~ /^[0-9]+$/
        or error __x"Invalid organisation {id}", id => $params{organisation};
    !defined $params{department_id} || $params{department_id} =~ /^[0-9]+$/
        or error __x"Invalid department {id}", id => $params{department_id};
    !defined $params{team_id} || $params{team_id} =~ /^[0-9]+$/
        or error __x"Invalid team {id}", id => $params{team_id};
    GADS::Util->email_valid($params{email})
        or error __x"The email address \"{email}\" is invalid", email => $params{email};

    my $values = {
        firstname             => $params{firstname},
        surname               => $params{surname},
        value                 => $params{value},
        email                 => $params{email},
        username              => $params{email},
        freetext1             => $params{freetext1},
        freetext2             => $params{freetext2},
        title                 => $params{title} || undef,
        organisation          => $params{organisation} || undef,
        department_id         => $params{department_id} || undef,
        team_id               => $params{team_id} || undef,
        account_request_notes => $params{account_request_notes},
    };

    my $audit = Linkspace::Audit->new;

    if (lc $values->{username} ne lc $self->username)
    {
        $self->result_source->schema->resultset('User')->active->search({
            username => $values->{username},
        })->count
            and error __x"Email address {username} already exists as an active user", username => $values->{username};
        $audit->login_change("Username ".$self->username." (id ".$self->id.") being changed to $values->{username}");
    }

    $values->{value} = _user_value($values);
    $self->update($values);

    $self->set_groups($params{groups})
        if $params{groups};

    if ($params{permissions})
    {
        error __"You do not have permission to set global user permissions"
            if !$current_user->permission->{superadmin};
        $self->permissions(@{$params{permissions}});
    }

    if(my $view_limits = $params{view_limits})
    {   my @view_limits = grep /\S/,
           ref $view_limits eq 'ARRAY' ? @$view_limits : $view_limits;
        $self->set_view_limits(\@view_limits);
    }

    my $msg = __x"User updated: ID {id}, username: {username}",
        id => $self->id, username => $params{username};
    $msg .= __x", groups: {groups}", groups => join ', ', @{$params{groups}}
        if $params{groups};
    $msg .= __x", permissions: {permissions}", permissions => join ', ', @{$params{permissions}}
        if $params{permissions};

    $audit->login_change($msg);

    $guard->commit;

}

sub permissions
{   my ($self, @permissions) = @_;

    my %user_perms = map { $_ => 1 } @permissions;
    my %all_perms  = map { $_->name => $_->id } $self->result_source->schema->resultset('Permission')->all;

    foreach my $perm (qw/useradmin audit superadmin/)
    {
        my $pid = $all_perms{$perm};
        if ($user_perms{$perm})
        {
            $self->find_or_create_related('user_permissions', { permission_id => $pid });
        }
        else {
            $self->search_related('user_permissions', { permission_id => $pid })->delete;
        }
    }
}

sub retire
{   my ($self, %options) = @_;

    my $site   = $::session->site;

    # Properly delete if account request - no record needed
    if ($self->account_request)
    {   $self->delete;
        return unless $options{send_reject_email};

        my $email = GADS::Email->instance;
        $email->send({
            subject => $site->email_reject_subject || "Account request rejected",
            emails  => [$self->email],
            text    => $site->email_reject_text || "Your account request has been rejected",
        });

        return;
    }

    $self->search_related(user_graphs => {})->delete;

    my $alerts = $self->search_related(alerts => {});
    my @alert_ids = map $_->id, $alerts->all;
    $::db->delete(AlertSend => { alert_id => \@alert_ids });
    $alerts->delete;

    $self->update({ lastview => undef });
    my $views    = $self->search_related(views => {});
    my @view_ids = map $_->id, $views->all;

    $::db->delete($_ => { view_id => \@view_ids })
        for qw/Filter ViewLayout Sort AlertCache Alert/;

    $views->delete;

    $self->update({ deleted => DateTime->now });

    if (my $msg = $site->email_delete_text)
    {
        my $email = GADS::Email->instance;
        $email->send({
            subject => $site->email_delete_subject || "Account deleted",
            emails  => [ $self->email ],
            text    => $msg,
        });
    }
}

sub has_draft
{   my ($self, $which) = @_;
    my $sheet_id = blessed $which ? $which->id : $which;
    $::db->search(Current => {
        instance_id  => $sheet_id,
        draftuser_id => $self->id,
        'curvals.id' => undef,
    }, {
        join => 'curvals',
    })->next;
}

sub _user_value
{   my $user      = shift or return;
    my $firstname = $user->{firstname} || '';
    my $surname   = $user->{surname}   || '';
    "$surname, $firstname";
}

sub export_hash
{   my $self = shift;
    # XXX Department, organisation etc not currently exported
    +{
        id                    => $self->id,
        firstname             => $self->firstname,
        surname               => $self->surname,
        value                 => $self->value,
        email                 => $self->email,
        username              => $self->username,
        freetext1             => $self->freetext1,
        freetext2             => $self->freetext2,
        password              => $self->password,
        pwchanged             => $self->pwchanged && $self->pwchanged->datetime,
        deleted               => $self->deleted && $self->deleted->datetime,
        lastlogin             => $self->lastlogin && $self->lastlogin->datetime,
        account_request       => $self->account_request,
        account_request_notes => $self->account_request_notes,
        created               => $self->created && $self->created->datetime,
        groups                => [map $_->id, $self->groups],
        permissions           => [map $_->permission->name, $self->user_permissions],
    };
}

1;

