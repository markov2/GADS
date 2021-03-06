use utf8;
package GADS::Schema::Result::Site;

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components("InflateColumn::DateTime");

__PACKAGE__->table("site");

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "host",
  { data_type => "varchar", is_nullable => 1, size => 128 },
  "name",
  { data_type => "text", is_nullable => 1 },
  "created",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 1,
  },
  "email_welcome_text",
  { data_type => "text", is_nullable => 1 },
  "email_welcome_subject",
  { data_type => "text", is_nullable => 1 },
  "email_delete_text",
  { data_type => "text", is_nullable => 1 },
  "email_delete_subject",
  { data_type => "text", is_nullable => 1 },
  "email_reject_text",
  { data_type => "text", is_nullable => 1 },
  "email_reject_subject",
  { data_type => "text", is_nullable => 1 },
  "register_text",
  { data_type => "text", is_nullable => 1 },
  "homepage_text",
  { data_type => "text", is_nullable => 1 },
  "homepage_text2",
  { data_type => "text", is_nullable => 1 },
  "register_title_help",
  { data_type => "text", is_nullable => 1 },
  "register_freetext1_help",
  { data_type => "text", is_nullable => 1 },
  "register_freetext2_help",
  { data_type => "text", is_nullable => 1 },
  "register_email_help",
  { data_type => "text", is_nullable => 1 },
  "register_organisation_help",
  { data_type => "text", is_nullable => 1 },
  "register_organisation_name",
  { data_type => "text", is_nullable => 1 },
  "register_organisation_mandatory",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_department_help",
  { data_type => "text", is_nullable => 1 },
  "register_department_name",
  { data_type => "text", is_nullable => 1 },
  "register_department_mandatory",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_team_help",
  { data_type => "text", is_nullable => 1 },
  "register_team_name",
  { data_type => "text", is_nullable => 1 },
  "register_team_mandatory",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_notes_help",
  { data_type => "text", is_nullable => 1 },
  "register_freetext1_name",
  { data_type => "text", is_nullable => 1 },
  "register_freetext2_name",
  { data_type => "text", is_nullable => 1 },
  "register_show_organisation",
  { data_type => "smallint", default_value => 1, is_nullable => 0 },
  "register_show_department",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_show_team",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "register_show_title",
  { data_type => "smallint", default_value => 1, is_nullable => 0 },
  "hide_account_request",
  { data_type => "smallint", default_value => 0, is_nullable => 0 },
  "remember_user_location",
  { data_type => "smallint", default_value => 1, is_nullable => 0 },
);

__PACKAGE__->set_primary_key("id");

__PACKAGE__->has_many(
  "audits",
  "GADS::Schema::Result::Audit",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "groups",
  "GADS::Schema::Result::Group",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "imports",
  "GADS::Schema::Result::Import",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "instances",
  "GADS::Schema::Result::Instance",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "organisations",
  "GADS::Schema::Result::Organisation",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "departments",
  "GADS::Schema::Result::Department",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "teams",
  "GADS::Schema::Result::Team",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "titles",
  "GADS::Schema::Result::Title",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

__PACKAGE__->has_many(
  "users",
  "GADS::Schema::Result::User",
  { "foreign.site_id" => "self.id" },
  { cascade_copy => 0, cascade_delete => 0 },
);

sub has_main_homepage
{   my $self = shift;
    return 1 if $self->homepage_text && $self->homepage_text !~ /^\s*$/;
    return 1 if $self->homepage_text2 && $self->homepage_text2 !~ /^\s*$/;
    return 0;
}

sub has_table_homepage
{   my $self = shift;
    foreach my $table ($self->instances)
    {
        return 1 if $table->homepage_text && $table->homepage_text !~ /^\s*$/;
        return 1 if $table->homepage_text2 && $table->homepage_text2 !~ /^\s*$/;
    }
    return 0;
}

sub organisation_name
{   my $self = shift;
    $self->register_organisation_name || 'Organisation';
}

sub department_name
{   my $self = shift;
    $self->register_department_name || 'Department';
}

sub team_name
{   my $self = shift;
    $self->register_team_name || 'Team';
}

1;
