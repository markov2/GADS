package Linkspace::Site;
use parent 'GADS::Schema::Result::Site';

use warnings;
use strict;

use Log::Report 'linkspace';

use Linkspace::Users    ();
use Linkspace::Document ();
use Linkspace::Group    ();

use List::Util   qw(first);

=head1 NAME
Linkspace::Site - manages one Site (set of Documents with Users)

=head1 SYNOPSIS

  my $site = $::session->site;

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


    my $rs = $class->create(\%insert);
    $class->from_id($rs->id);
}

=head2 $class->site_delete(%which);
=cut

sub site_delete($)
{   my ($class, $site_id) = @_;
    Linkspace::Users->site_delete($site_id);
    $::db->delete(Groups => { instance_id => $site_id });
}

#-------------------------
=head1 METHODS: Site Users
There is a lot of action around user, so this is implemented in helper module
L<Linkspace::Users>

=head2 my $users = $site->users;
=cut

has users => (
    is      => 'lazy',
    isa     => 'Linkspace::Users',
    builder => sub { Linkspace::Users->new(site => $self) },
);

=head2 my @groups = @{$site->groups};
=cut

has groups => (
    is      => 'lazy',
    builder => sub {
        my $groups_rs = $::db->search(Group => {}, { order_by => 'me.name' });
        [ map Linkspace::Group->from_record($_), $groups_rs->all ];
    },
}

=head2 my $group = $site->group($id);

=head2 my $group = $site->group_by_name($name);
Returns a L<Linkspace::Group>.
=cut

sub group($)
{   my ($self, $id) = @_;
    first { $_->id == $id } $self->groups;
}

sub group_by_name($)
{   my ($self, $name) = @_;
    first { $_->name eq $name } $self->groups;
}

=head2 $site->group_create(%insert|\%insert);
=cut

sub group_create(%)
{   my $self = shift;
    Linkspace::Group->group_create(@_);
}

#-------------------------
=head1 METHODS: Site sheets

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
