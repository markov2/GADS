package Linkspace::Site;
use parent 'GADS::Schema::Result::Site';

use Moo;

use warnings;
use strict;

use Log::Report 'linkspace';

use Linkspace::Site::Users ();
use Linkspace::Document ();    # only a single document, so no manager object

use List::Util   qw(first);

=head1 NAME
Linkspace::Site - manages one Site (set of Documents with Users)

=head1 SYNOPSIS

  my $site  = $::session->site;
  my $users = $site->users;

=head1 DESCRIPTION
Manage a single "Site": a set of sheets with data, accessed by users.

There may be more than one separate site in a single Linkspace database
instance, therefore the top-level tables have a C<site_id> column.

=head1 METHODS: Constructors

=head2 my $site = Linkspace::Site->from_record($record, %options);
=cut

sub from_record($)
{   my ($class, $record) = @_;
    my $self = bless $record, $class;

    # The site may have changed since the last time we used it (while
    # processing the previous request).
    $::db->schema->setup_site($self);
    $self;
}

=head2 my $site = Linkspace::Site->from_id($id, %options);
=cut

sub from_id($%)
{   my ($class, $id) = (shift, shift);
    my $record = $::db->get_record(Site => $id) or return;
    $record ? $class->from_record($record) : undef;
}

=head2 my $site = Linkspace::Site->find($hostname, %options);
Create the object from the database.  Sites are globally maintained

=cut

sub find($%) {
	my ($class, $host) = (shift, shift);
	my $record = $::db->search(Site => { host => $host })->single;
    $record ? $class->from_record($record) : undef;
}

=head2 my $site = $class->site_create(%);
Create a new site object in the database.
=cut

sub site_create(%)
{   my ($class, %insert) = @_;
    $insert{register_organisation_name} ||= 'Organisation';
    $insert{register_department_name}   ||= 'Department';
    $insert{register_team_name}         ||= 'Team';

    $insert{email_welcome_subject}      ||= 'Your new account details';
    $insert{email_welcome_text}         ||= <<__WELCOME_TEXT;
An account for [NAME] has been created for you. Please
click on the following link to retrieve your password:

[URL]
__WELCOME_TEXT

    my $site_id = $::db->create(Site => \%insert)->id;
    $class->from_id($site_id);
    $self->changed('meta');
}

=head2 $self->site_update
XXX

=head2 $self->site_delete;
=cut

sub site_delete()
{   my $self = @_;
    $self->users->site_unuse($self);
    $self->document->site_unuse($self);
    $self->changed('meta');
    $self->delete;
}

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

has last_check => (is => 'rw');
my %_component_loaded;  # global

sub refresh
{	my $self = shift;
    $::linkspace->db->schema->update_fields($self);

return;
    my $now  = time;
    my @versions = $::db->search(ComponentVersions => {
        site_id => $self->id,
        updated => { \'>', $self->last_check },
    }, { column => 'label' })->all;
    $self->last_check($now);

    foreach my $change (@versions)
    {   delete $_component_loaded{$_} or next;

        if($change eq 'user') { undef $self->{users} }
        elsif($change =~ /^sheet_(\d+)/c) { $doc->sheet_restart($1) }
    }
    $self;
}

=head2 $site->changed($component);
Flag to other processes that a certain component has changed.  Any change
will cause a new version, which is simply a timestamp.
=cut

sub changed($)
{   my ($self, $component) = @_;
return;
    $::db->update_or_create(ComponentVersions => {
         site => $self->id, component => $component
    });
    #XXX to be implemented.  Needs to be done in the database!
    # ComponentVersions table has
    # mysql: "last_change TIMESTAMP
    #      NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP"
    # on psql via a trigger
    # https://x-team.com/blog/automatic-timestamps-with-postgresql/
}

=head2 $site->component_loaded($component);
Register the time-stamp when certain components were loaded, to be able
to clear the caches when they get too old. Refreshing will only happen
at the start of new requests, and may be very blunt.
=cut

sub component_loaded($)
{   my ($self, $component) = @_;
    $component_loaded{$self->id.'_'.$component} = time;
}

#-------------------------
=head1 METHODS: Site Users
The L<Linkspace::Site::Users> class manages Users, Groups and Permissions

=head2 my $users = $site->users;
=cut

sub users()
{   $_[0]->{users} ||= do {
        my $self = shift;
        $self->component_loaded('users');
        Linkspace::Site::Users->new(site => $self);
    };
);

sub groups { $_[0]->users }    # managed by the same helper object

#-------------------------
=head1 METHODS: Manage Documents

=head2 my $document = $site->document;
Returns the L<Linkspace::Document> object which manages the sheets for
this site.
=cut

has document => (
    is      => 'lazy',
    builder => sub { inkspace::Document->new(site => $_[0]) },
);

=head2 my $sheet = $site->sheet($which, %options);

Returns the sheet with that (long or short) name or id.  Have
a look at L<Linkspace::Document> method C<sheet()> for the C<%options>.
=cut

sub sheet($%) { shift->document->sheet(@_) }

1;
