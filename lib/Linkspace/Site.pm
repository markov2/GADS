package Linkspace::Site;
use parent 'GADS::Schema::Result::Site';

use warnings;
use strict;

use Log::Report 'linkspace';

use Linkspace::Users    ();
use Linkspace::Document ();

=head1 NAME
Linkspace::Site - manages one Site (set of Documents with Users)

=head1 SYNOPSIS

  my $site = $::session->site;

=head1 DESCRIPTION
Manage a single "Site": a set of sheets with data, accessed by users.

There may be more than one separate site in a single Linkspace database
instance, therefore the top-level tables have a C<site_id> column.

=head1 METHODS: Constructors

=head2 my $site = Linkspace::Site->find($hostname);
Create the object from the database.  Sites are globally maintained

=cut

sub find {
	my ($class, $host) = @_;

    #XXX must match case-insens
	my $site = $::db->search(Site => { host => $host })->first
		or return ();

    my $self = bless $site, $class;
    $::db->schema->setup_site($site);

    $self;
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


=head1 METHODS: Site presentation
=cut

sub organisation_name { shift->register_organisation_name || 'Organisation' }
sub department_name   { shift->register_department_name   || 'Department' }
sub team_name         { shift->register_team_name         || 'Team' }


=head1 METHODS: Site dependent components

=head2 my $users = $site->users;
=cut

sub users
{   my $self = shift;
    $self->{_users} = Linkspace::Users->new(site => $self);
}

=head2 my $document = $site->document;
Returns the L<Linkspace::Document> object which manages the sheets for
this site.
=cut

sub document()
{   my $self = shift;
    $self->{LS_sheets} ||= Linkspace::Document->new(site => $self);
}


=head2 my $sheet = $site->sheet($name, %options);

=head2 my $sheet = $site->sheet($id, %options);

Returns the sheet with that (long or short) C<$name> or C<$id>.  Have
a look at L<Linkspace::Document> method C<sheet()> for the C<%options>.
=cut

sub sheet($%)
{   my $self = shift;
    $self->document->sheet(@_);
}

1;
