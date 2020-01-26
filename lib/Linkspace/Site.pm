package Linkspace::Site;
use parent 'GADS::Schema::Result::Site';

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
    $record ? $self->from_record($record) : undef;
}

=head2 my $site = Linkspace::Site->find($hostname, %options);
Create the object from the database.  Sites are globally maintained

=cut

sub find($%) {
	my ($class, $host) = (shift, shift);
	my $record = $::db->search(Site => { host => $host })->single;
    $record ? $class->from_record($record) : undef;
}

=head2 $site->refresh;
When you are re-using the site object, you may miss information altered
by other sessions.  Calling refresh will re-synchronize the site status,
especially schema changes.
=cut

sub refresh
{	my $self = shift;
    $::linkspace->db->schema->update_fields($self);
    $self;
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
__WELCOME

    my $site_id = $::db->create(Site => \%insert)->id;
    $class->from_id($site->id);
}

=head2 $self->site_delete(%which);
=cut

sub site_delete($)
{   my ($class, $site_id) = @_;
    $self->users->site_unuse($site);
    $self->document->site_unuse($site);
}

#-------------------------
=head1 METHODS: Site Users
The L<Linkspace::Site::Users> class manages Users, Groups and Permissions

=head2 my $users = $site->users;
=cut

has users => (
    is      => 'lazy',
    builder => sub { Linkspace::Site::Users->new(site => $self) },
);

sub groups { $_[0]->users }

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
