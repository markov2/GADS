package Linkspace::Site;

use warnings;
use strict;

use Log::Report 'linkspace';
use List::Util   qw(first);

use Linkspace::Site::Users ();
use Linkspace::Site::Document ();  # only a single document, so no manager object

use Moo;
extends 'Linkspace::DB::Table';

=head1 NAME
Linkspace::Site - manages one Site (set of Documents with Users)

=head1 SYNOPSIS

  my $site  = $::session->site;
  my $users = $site->users;

=head1 DESCRIPTION
Manage a single "Site": a set of sheets with data, accessed by users.

There may be more than one separate site in a single Linkspace database
instance, therefore the top-level tables have a C<site_id> column.
=cut

sub db_table { 'Site' }

sub db_field_rename { +{
    host => 'hostname',
    hide_account_request       => 'do_hide_account_requests',
    register_show_department   => 'do_show_department',
    register_show_organisation => 'do_show_organisation',
    register_show_team         => 'do_show_team',
    register_show_title        => 'do_show_title',
    remember_user_location     => 'do_remember_user_location',
}; }

__PACKAGE__->db_accessors;

### 2020-04-18: columns in GADS::Schema::Result::Site
# id                              register_freetext1_name
# name                            register_freetext2_help
# created                         register_freetext2_name
# email_delete_subject            register_notes_help
# email_delete_text               register_organisation_help
# email_reject_subject            register_organisation_mandatory
# email_reject_text               register_organisation_name
# email_welcome_subject           register_show_department
# email_welcome_text              register_show_organisation
# hide_account_request            register_show_team
# homepage_text                   register_show_title
# homepage_text2                  register_team_help
# host                            register_team_mandatory
# register_department_help        register_team_name
# register_department_mandatory   register_text
# register_department_name        register_title_help
# register_email_help             remember_user_location
# register_freetext1_help

=head1 METHODS: Constructors

=head2 my $site = Linkspace::Site->from_hostname($hostname, %options);
Create the object from the database.  Sites are globally maintained

=cut

sub from_hostname($%)
{   my ($class, $host) = (shift, shift);
    defined $host or return undef;
	my $record = $::db->get_record(Site => { host => $host });
    $record ? $class->from_record($record) : undef;
}

=head2 my $site = Linkspace::Site->from_name($name, %options);
Create the object from the database.  Sites are globally maintained

=cut

sub from_name($%)
{   my ($class, $name) = (shift, shift);
    defined $name or return undef;
	my $record = $::db->get_record(Site => { name => $name });
    $record ? $class->from_record($record) : undef;
}

=head2 my $site = $class->site_create(\%insert, %options);
Create a new site object in the database.
=cut

sub site_create($%)
{   my ($class, $insert) = (shift, shift);
    my $host = $insert->{hostname} or panic;
    $insert->{name}    ||= $host =~ s/\..*//r;
    $insert->{created} ||= DateTime->now;

    #XXX From config?
    $insert->{register_organisation_name} ||= 'Organisation';
    $insert->{register_department_name}   ||= 'Department';
    $insert->{register_team_name}         ||= 'Team';
    $insert->{email_welcome_subject}      ||= 'Your new account details';
    $insert->{email_welcome_text}         ||= <<__WELCOME_TEXT;
An account for [NAME] has been created for you. Please
click on the following link to retrieve your password:

[URL]
__WELCOME_TEXT

    my $self = $class->create($insert, @_) or return;
    $self->changed('meta');
    $self;
}

=head2 $self->site_update(\%changes, %options);
Change site settings.
=cut

sub site_update($%)
{   my ($self, $update) = (shift, shift);
    # No need to support updating childs in one go.

    $self->update($update, @_);
    $self->changed('meta');
    $self;
}

=head2 $self->site_delete;
=cut

sub site_delete()
{   my $self = shift;
    $self->users->site_unuse($self);
    $self->document->site_unuse($self);
    $self->changed('meta');   # signal to cache
    $self->delete;
}

#-------------------------
=head1 METHODS: Accessors
=cut

sub path { substr $_[0]->name // $_[0]->hostname, 0, 10 }

#-------------------------
=head1 METHODS: Caching
We like to cache as much information as possible between requests,
but need to immediately see changes in other processes.  Therefore,
the database has a table which keeps versions of configuration of
each of the large components: on any (small) change, the cached object
structure related to that (large) component get's totally trashed in
all other processes.

For now, the planned components are 'site', 'users' and 'sheet_$id'.

=head2 $site->refresh;
When you are re-using the site object, you may miss information altered
by other sessions.  Calling refresh will re-synchronize the site status,
especially schema changes.
=cut

has last_check => (is => 'rw', default => sub { time });

sub refresh
{	my ($self, @components) = @_;

    my %c;
    if(@components)
    {   $c{$_}++ for @components;
    }
    else
    {   # collect changes from abroad
        my $now  = time;
#XXX table does not exist yet
        $c{$_}++ for $::db->search(ComponentVersions => {
            site_id => $self->id,
            updated => { \'>', $self->last_check },
        }, { column => 'component' })->all;
        $self->last_check($now);
    }

    if($c{columns})
    {   $::db->schema->update_fields($self);  # schema changes
        undef $self->{document};              # affects all sheets
    }

    undef $self->{users} if $c{users} || $c{groups};
    $self->document->sheet_refresh($_) for grep /^sheet_/, keys %c;
    $self;
}

=head2 $site->changed($component);
Flag to other processes that a certain component has changed.  Any change
will cause a new version, which is simply a timestamp.
=cut

sub changed($)
{   my ($self, $component) = @_;
    $self->{LS_changed}{$component}++;
return;
    $::db->update_or_create(ComponentVersions => {
         site      => $self->id,
         component => $component,
    });
    #XXX to be implemented.  Needs to be done in the database!
    # ComponentVersions table has
    # mysql: "last_change TIMESTAMP NOT NULL
    #     CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP"
    #   + site_id + component TEXT
    # on psql via a trigger
    # https://x-team.com/blog/automatic-timestamps-with-postgresql/
}

=head2 my $is_changed = $site->has_changed($component, $bool?);
When a bool is given, it will be used to change the value.  The old value is
returned.
=cut

sub has_changed($;$){
    my ($self, $component, $new) = @_;
    my $changes = $self->{LS_changed};
    my $has     = $changes->{$component} || 0;
    $changes->{$component} = $new if @_==3;
    $has;
}

#-------------------------
=head1 METHODS: Site Users
The L<Linkspace::Site::Users> class manages Users, Groups and Permissions

=head2 my $users = $site->users;
=cut

sub users() { $_[0]->{users} ||= Linkspace::Site::Users->new(site => $_[0]) }
sub groups  { $_[0]->users }    # managed by the same helper object

#-------------------------
=head1 METHODS: Company information
Manage tables Organization, Department, Team, and Title: which define
the working position of a person.

=head2 my $id = $site->workspot_create($set, $name);
=cut

### 2020-04-29: columns in GADS::Schema::Result::Team
# id         name       site_id

sub workspot_create($$)
{   my ($self, $set, $name) = @_;
    $self->_record->create_related("${set}s" => { name => $name })->id;
}

sub workspot($$)
{   my ($self, $set, $name) = @_;
    $::db->get_record(ucfirst $set => { name => $name });
}

sub departments   { [ sort { $a->name cmp $b->name } $_[0]->_record->departments ] }
sub organisations { [ sort { $a->name cmp $b->name } $_[0]->_record->organisations ] }
sub teams         { [ sort { $a->name cmp $b->name } $_[0]->_record->teams ] }
sub titles        { [ sort { $a->name cmp $b->name } $_[0]->_record->titles ] }

sub validate_workspot($)
{   my ($self, $values) = @_;
    ! $self->register_organisation_mandatory || is_valid_id $values->{organisation_id}
        or error __x"Please select a {name} for the user", name => $self->organisation_name;

    ! $self->register_team_mandatory || is_valid_id $values->{team_id}
        or error __x"Please select a {name} for the user", name => $self->team_name;

    ! $self->register_department_mandatory || is_valid_id $values->{department_id}
        or error __x"Please select a {name} for the user", name => $self->department_name;
}

sub workspot_field_titles()
{   my $self = shift;
  [ ($self->do_show_title        ? 'Title'                  : ()),
    ($self->do_show_organisation ? $self->register_organisation_name : ()),
    ($self->do_show_department   ? $self->register_department_name   : ()),
    ($self->do_show_team         ? $self->register_team_name         : ()),
    do {my $r = $self->register_freetext1_name; $r ? $r : ()},
    do {my $r = $self->register_freetext2_name; $r ? $r : ()},
  ];
}

sub workspot_field_names()
{   my $self = shift;
  [ ($self->do_show_title        ? 'title'        : ()),
    ($self->do_show_organisation ? 'organisation' : ()),
    ($self->do_show_department   ? 'department'   : ()),
    ($self->do_show_team         ? 'team'         : ()),
    ($self->register_freetext1_name ? 'freetext1' : ()),
    ($self->register_freetext2_name ? 'freetext2' : ()),
  ];
}


#-------------------------
=head1 METHODS: Manage Documents
Sheets are grouped into Documents: a set of sheets which belong together
in a project.  It shares the Users and Group definitions of a department
but the content is totally independent.  However... this is not supported
yet: you need to create new Sites for such purpose.

=head2 my $document = $site->document;
Returns the L<Linkspace::Site::Document> object which manages the sheets for
this site.
=cut

has document => (
    is      => 'lazy',
    builder => sub { Linkspace::Site::Document->new(site => $_[0]) },
);

=head2 my $sheet = $site->sheet($which, %options);
Returns the sheet with that (long or short) name or id.  Have
a look at L<Linkspace::Site::Document> method C<sheet()> for the C<%options>.
=cut

sub sheet($%) { shift->document->sheet(@_) }

1;
