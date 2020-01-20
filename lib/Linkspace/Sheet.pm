=pod
GADS
Copyright (C) 2015 Ctrl O Ltd

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
=cut

package Linkspace::Sheet;
use base 'GADS::Schema::Result::Instance';

use Log::Report  'linkspace';
use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
use Clone        'clone';

use Algorithm::Dependency::Source::HoA ();
use Algorithm::Dependency::Ordered ();

###!!!!  The naming is confusing, because that's legacy.
###  table Instance      contains Sheet data
###  table InstanceGroup relates Sheets to Users

=head1 NAME
Linkspace::Sheet - manages one sheet: one table with a Layout

=head1 SYNOPSIS

  my $doc = $::session->site->document;
  my @sheets = $doc->all_sheets;

  my $sheet  = $doc->get_sheet($id);

=head1 DESCRIPTION

=head1 METHODS: Constructors

=head2 my $sheet = Linkspace::Sheet->new(%options);
Option C<allow_everything> will overrule access permission checking.
Required is a C<document>.
=cut

=head2 my $sheet = Linkspace::Sheet->from_record($record, %options);
The C<%options> are passed to C<new()>.
=cut

sub from_record
{   my ($class, $record, %args) = @_;
    $class->new( { %$record, %args } );
}

=head2 my $sheet = $class->from_id($sheet_id, %options);
Create a Sheet object based on a C<$sheet_id> (old name: instance_id).
The same C<%options> as method C<from_record()>.
=cut

sub from_id
{   my ($class, $sheet_id, %args) = @_;
    $class->from_record($::db->get_record(Instances => $sheet_id), %args);
}

=head2 my $new_sheet = $sheet->update(\%changes, %options);
Apply the changes to the sheet's database structure.  For now, this can
only change the sheet (Instance) record, not its dependencies.

The whole sheet will be instantiated again, to get the default set by
the database and to clear all the cacheing.  But when there are no
changes to the record, it will return the original object.
=cut

sub update($)
{   my ($self, $changes, %args) = @_;
    keys %$changes or return $self;

    $::db->update(Instance => $self, $changes);
    (ref $self)->from_record(
        $::db->get_record(Instances => $self->id),
        layout   => $self->layout,
        document => $self->document,
        $args,
    );
}

=head1 METHODS: Accessors

=head2 my $doc = $sheet->document;
The Site where the User has logged-in contains Sheets which are clustered
into Documents (at the moment, only one Document per Site is supported)
=cut

has document => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);

=head1 METHODS: the Sheet itself

=cut

=head2 $sheet->delete;
Remove the sheet.
=cut

sub delete($)
{   my $self     = shift;
    my $sheet_id = $self->id;
    my $layout   = $self->layout;

    my $guard    = $::db->begin_work;

    $_->delete
       for $self->layout->columns(only_internal => 1, include_hidden => 1);

    $::db->delete(InstanceGroup => { instance_id => $sheet_id });

    my $dash = $::db->search(Dashboard => { instance_id => $sheet_id });
    $::db->delete(Widget => { dashboard_id =>
       { -in => $dash->get_column('id')->as_query }});

    $dash->delete;
    $::db->delete(Instance => $sheet_id);

    $guard->commit;
}

=head2 $sheet = $class->create(%settings);
Create a new sheet object, which is saved to the database with its
initial C<%settings>.
=cut

sub create($%)
{   my ($class, %settings) = @_;
    my $sheet_id = $::db->create(Instance => \%settings)->id;

    my %layout_defaults;  #XXX how do I get them?
	Linkspace::Layout->create_for_sheet($self, %layout_defaults);

    # Start with a clean sheet
    $class->from_id($sheet_id);
}


=head2 my $layout = $sheet->layout;
Each Sheet has a Layout which contains the Column descriptions.
=cut

has layout => (
    is => 'lazy',
    builder => sub {
        my $self = shift;
        $self->document->layout_for_sheet($self);
    },
);

=head2 my $layout = $sheet->create_layout($insert, %options);
=cut

sub create_layout($%)
{   my ($self, $insert, %args) = @_;
    Linkspace::Layout->create_layout($insert, %args);
        $layout->create_internal_columns;

    $_->{group_id} = $group_mapping->{$_->{group_id}}
        for @{$instance_info->{permissions}};

    $layout->import_hash($sheet_info, report_only => $report_only);
    $layout->write unless $report_only;

}

=head1 METHODS: Keeping records

=head2 $sheet->blank_fields(%search);
Find columns which match the C<%search>, and set those values to blank ('').
=cut

sub blank_records(%)
{   my $self = shift;
    $self->data->blank_fields($self->columns(@_));
}

=head1 METHODS: permission management
=cut

my @sheet_permissions = qw/
    bulk_update
    create_child
    delete
    download
    layout
    link
    message
    purge
    view_create
    view_group
    view_limit_extra
/;

my %is_valid_permission = map +($_ => 1), @sheet_permissions;
my %superadmin_rights   = map +($_ => 1), qw/layout view_create/;

=head2 $sheet->set_allow_everything(1);

=head2 my $overrule_permissions = $sheet->allow_everything;
When set, permissions for do anything are overruled.
=cut

has allow_everything => (
    is       => 'rw',
    isa      => Bool,
    default  => 0,
);

# The index contains a HASH of permissions per (user)group_id.
has _permission_index => (
    is      => 'lazy',
    isa     => HashRef,
    builder => sub {
        my $self = shift;
        my %perms = map +($_->group_id => $_->permission),
            $::db->search(InstanceGroup => { instance_id => $self->id })->all;
        \%perms;
    },
);

=head2 $sheet->set_permissions(@perms|\@perms);
Change the Sheet wide permissions for Groups.  There are also (user)group
permissions which span multiple sheets, and column specific permissions.

The C<@perms> are in the form C<< ${group_id}_${permission} >>, probably
directly from a web-form.
=cut

sub set_permissions
{   my $self  = shift;
    my @perms = ref $_[0] eq 'ARRAY' ? @{$_[0]} : @_;

    my $sheet_id = $self->id;
    my $index    = $self->_permission_index;

    my %missing  = clone %$index;

	my @create;
    foreach my $perm (@perms)
    {   my ($group_id, $permission) = $perm =~ /^([0-9]+)\_(.*)/;
        $group_id && $is_valid_permission{$permission}
            or panic "Invalid permission $perm";

        next if delete $missing{$group_id}{$permission};

		$index->{$group_id}{$permission} = 1;
		push @create, +{
            instance_id => $sheet_id,
            group_id    => $group_id,
            permission  => $permission,
        };
    }

    my @delete;
    foreach my $group_id (keys %missing)
    {   push @delete, map +{ 
            instance_id => $sheet_id,
            group_id    => $group_id,
            permission  => $_,
        }, keys $missing{$group_id};
    }

    @create || @delete or return;

    my $guard = $::db->begin_work;
    $::db->resultset('InstanceGroup')->populate(\@create) if @create;
    $::db->delete(InstanceGroup => \@delete) if @delete;
    $guard->commit;
}

=head2 my $allowed = $sheet->user_can($perm, [$user]);
Check whether a certain C<$user> (defaults to the session user) has
a specific permission flag.

Most components of the program should try to avoid other access check
routines: where permissions reside change.

=cut

sub user_can($;$)
{   my ($self, $permission, $user) = @_;
    $user ||= $::session->user;

      $self->allow_everything
    ? 1
    : $is_valid_permission{$permission}
    ? $self->_permission_index->{$user->group_id}{$permission}
    : $user->is_permitted('superadmin') && $superadmin_rights{$permission}
    ? 1
    : $user->is_permitted($permission);
}

=head2 my $page = $sheet->get_page(%options);
Return a L<Linkspace::Page> based on the sheet data.
=cut

#XXX This may need to move to Document, when searches cross sheets

sub get_page($)
{   my ($self, %args) = @_;
    my $views = $self->views;

    $args{view_limits} =
       [ map $views->view($_->view_id), $views->limits_for_user ];

    my $view_limit_extra_id
      = $self->user_can("view_limit_extra")
      ? $option{view_limit_extra_id}
      : $self->layout->default_view_limit_extra_id;

    $args{view_limit_extra} = $views->view($view_limit_extra_id);

    $self->data->search(%args);
}

=head1 METHODS: MetricGroup administration

=cut

sub metric_group {...}
sub create_metric_group { $metric_group->import_hash($mg) }

1;
