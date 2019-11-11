package Linkspace::Site;
use parent 'GADS::Schema::Result::Site';

use warnings;
use strict;

use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use List::Util qw/first/;

use Linkspace::Users;

=head1 NAME
Linkspace::Site - manages one Site (set of Documents with Users)

=head1 SYNOPSIS

  my $site = session->site;

=head1 DESCRIPTION
Manage a single "Site": a set of Documents with Data, accessed by Users.

There may be more than one separate site in a single Linkspace database
instance, therefore most of the tables have a C<site_id> column.

=head1 METHODS: Constructors

=head2 my $site = Linkspace::Site->find($hostname);
Create the object from the database.  Sites are globally maintained

=cut

sub find {
	my ($class, $host) = @_;

    my $rs   = $::linkspace->db->resultset('Site');
	my $site = $rs->search({ host => $host })->next #XXX must match case-insens
		or return ();

    my $self = bless $site, $class;

    $self->{schema} = $::linkspace->db->generic_schema->clone->setup($self);

    $self;
}


=head1 METHODS: Database

=head2 my $schema = $site->schema;
=cut

sub schema { $_[0]->{schema} }

=head2 $site->refresh
When you are re-using the site object, you may miss information altered
by other sessions.  Calling refresh will re-synchronize the site status,
especially schema changes.
=cut

sub refresh {
	my $self = shift;
    $self->schema->update_fields($self);
    $self;
}

=head2 my $rs = $site->resultset($table);
=cut

sub resultset
{   my ($self, $table) = @_;
    $self->schema->resultset($table)->search_rs({'me.site_id' => $self->id});
}

=head2 my $results = $site->search($table, @more);
Search for (site related) records in the C<$table>.  You may pass C<@more>
parameters for the search.
=cut

sub search
{   my ($self, $table) = (shift, shift);
    $self->resultset($table)->search(@_);
}

=head2 $site->create($table, \%data);
Create a (site related) record in the C<$table>, containing C<%data>.
=cut

sub create
{   my ($self, $table, $data) = @_;
    $self->resultset($table)->create($data);
}

=head2 $site->delete($table, \%search);
Delete from C<$table> all matching records.
=cut

sub delete
{   my ($self, $table) = (shift, shift);
    $self->resultset($table)->search(@_)->delete;
}

=head1 METHODS: Site presentation
=cut

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

=head1 METHODS: Site dependent components

=head2 my $users = $site->users;
=cut

sub users
{    my $self = shift;
     $self->{_users} = Linkspace::Users->new(site => $self);
}

1;
