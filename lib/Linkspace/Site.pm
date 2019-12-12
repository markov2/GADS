package Linkspace::Site;
use parent 'GADS::Schema::Result::Site';

use warnings;
use strict;

use Log::Report 'linkspace';

use Linkspace::Users  ();
use Linkspace::Sheets ();

=head1 NAME
Linkspace::Site - manages one Site (set of Documents with Users)

=head1 SYNOPSIS

  my $site = $::session->site;

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

    my $db   = $::linkspace->db;

    #XXX must match case-insens
	my $site = $db->resultset('Site')->search({ host => $host })->next
		or return ();

    my $self = bless $site, $class;
    $db->schema->setup_site($site);

    $self;
}


=head1 METHODS: Database

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

=head2 my $rs = $site->resultset($table);
=cut

sub resultset
{   my ($self, $table) = @_;
    $self->{_rs}{$table} ||= $::linkspace->db->schema->resultset($table)
        ->search_rs({'me.site_id' => $self->id});
}

=head2 my $results = $site->search($table, @more);
Search for (site related) records in the C<$table>.  You may pass C<@more>
parameters for the search.
=cut

sub search
{   my ($self, $table) = (shift, shift);
    $self->resultset($table)->search(@_);
}

=head2 my $result = $site->get_record($table, $id);
Returns one result HASH.
=cut

sub get_record($$)
{   my ($self, $table, $id) = @_;
    $self->resultset($table)->search({id => $id})->next;
}

=head2 my $result = $site->create($table, \%data);
Create a (site related) record in the C<$table>, containing C<%data>.
=cut

sub create
{   my ($self, $table, $data) = @_;
    $self->resultset($table)->create($data);
}


=head2 $site->delete($table, \%search);

=head2 $site->delete($table, $id);

Delete from C<$table> all matching records.
=cut

sub delete
{   my ($self, $table, $search) = (shift, shift, shift);
    $search = +{ id => $search } unless ref $search eq 'HASH';
    $self->resultset($table)->search($search, @_)->delete;
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

=head2 my $sheets = $site->sheets;
Returns the L<Linkspace::Sheets> object which manages the sheets for
this site.
=cut

sub sheets()
{   my $self = shift;
    $self->{_sheets} ||= Linkspace::Sheets->new(site => $self);
}


=head2 my $sheet = $site->sheet($name, %options);

=head2 my $sheet = $site->sheet($id, %options);

Returns the sheet with that (long or short) C<$name> or C<$id>.  Have
a look at L<Linkspace::Sheets> method C<sheet()> for the C<%options>.
=cut

sub sheet($%)
{   my $self = shift;
    $self->sheets->sheet(@_);
}

1;
