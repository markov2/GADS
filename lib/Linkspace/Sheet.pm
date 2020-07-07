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

use Log::Report  'linkspace';
use Clone        'clone';
use Algorithm::Dependency::Source::HoA ();
use Algorithm::Dependency::Ordered ();

use Linkspace::Sheet::Layout ();
#use Linkspace::Sheet::Data   ();
#use Linkspace::Sheet::Views  ();
#use Linkspace::Sheet::Graphs ();

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;
extends 'Linkspace::DB::Table';

###!!!!  The naming is confusing, because that's legacy.
###  table Instance      contains Sheet data
###  table InstanceGroup relates Sheets to Users

sub db_table { 'Instance' }

sub db_fields_unused { [ qw/no_overnight_update/ ] }
#XXX no_hide_blank cannot be changed

sub db_field_rename { +{
    sort_layout_id => 'sort_column',
}; }

### 2020-04-22: columns in GADS::Schema::Result::Instance
# id                          homepage_text
# name                        homepage_text2
# site_id                     name_short
# api_index_layout_id         no_hide_blank
# default_view_limit_extra_id no_overnight_update
# forget_history              sort_layout_id
# forward_record_after_create sort_type

sub db_also_bools { [ qw/
    forget_history
    forward_record_after_create
/ ] }

__PACKAGE__->db_accessors;

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

=head2 $sheet->sheet_update(\%changes);
Apply the changes to the sheet's database structure.  For now, this can
only change the sheet (Instance) record, not its dependencies.

The whole sheet will be instantiated again, to get the default set by
the database and to clear all the cacheing.  But when there are no
changes to the record, it will return the original object.
=cut

sub sheet_update($)
{   my ($self, $changes) = @_;
    $self->validate($changes);
    $self->update($changes);
}

=head2 my $changes = $class->validate(\%data);
=cut

sub validate($)
{   my ($thing, $insert) = @_;
    my $slid = $insert->{sort_column_id};
    ! defined $slid || is_valid_id $slid
        or error __x"Invalid sheet sort_layout_id '{id}'", id => $slid;

    my $st = $insert->{sort_type};
    ! defined $st || $st eq 'asc' || $st eq 'desc'
        or error __x"Invalid sheet sort type {type}", type => $st;

    $insert;
}

=head2 $sheet->sheet_delete;
Remove the sheet.
=cut

sub sheet_delete($)
{   my $self     = shift;
    my $sheet_id = $self->id;

    $self->site->users->sheet_unuse($self);
    $self->layout->sheet_unuse($self);

    my $dash = $::db->search(Dashboard => { instance_id => $sheet_id });
    $::db->delete(Widget => { dashboard_id =>
       { -in => $dash->get_column('id')->as_query }});
    $dash->dashboard_delete;

    $self->delete;
}

=head2 $sheet = $class->sheet_create(\%settings, %args);
Create a new sheet object, which is saved to the database with its
initial C<%settings>.
=cut

sub sheet_create($%)
{   my ($class, $insert, %args) = @_;
    my $self = $class->create($insert, %args);

    $self->layout->insert_initial_columns;
    $self;
}

#--------------------
=head1 METHODS: Generic accessors

=head2 my $doc = $sheet->document;
The Site where the User has logged-in contains Sheets which are clustered
into Documents (at the moment, only one Document per Site is supported)
=cut

has document => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);

=head2 my $label = $sheet->identifier;
=cut

sub identifier { $_[0]->name_short || 'table'.$_[0]->id }

sub path { $_[0]->site->path.'/'.$_[0]->identifier }

#--------------------
=head1 METHODS: Sheet Layout
Each Sheet has a Layout object which manages the Columns.  It is a management
object without its own database table; table 'Layout' contains Columns.

=head2 my $layout = $sheet->layout;
=cut

has layout => (
    is      => 'lazy',
    builder => sub { Linkspace::Sheet::Layout->new(sheet => $_[0]) },
);

#--------------------
=head1 METHODS: Sheet Data, Keeping records
Each Sheet has a Data object to maintain it's data.  It does not have it's
own table but maintains the 'Records' table.

=head2 my $data = $sheet->data;
=cut

has data => (
    is      => 'lazy',
    builder => sub { Linkspace::Sheet::Data->new(sheet => $_[0]) },
);

=head2 $sheet->blank_fields(%search);
Find columns which match the C<%search>, and set those values to blank ('').
=cut

sub blank_records(%)
{   my $self = shift;
    $self->data->blank_fields($self->columns_search(@_));
}

#----------------------
=head1 METHODS: Sheet permissions
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

# The index contains a HASH of permissions per (user)group_id.
has _permission_index => (
    is      => 'lazy',
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

=head2 $sheet->is_writable($user?);
Returns true when the user has 'layout' rights or is admin; simplification
of C<<$sheet->user_can('layout')>>.
=cut

sub is_writable(;$) { $_[0]->user_can(layout => $_[1]) }

=head2 my $page = $sheet->get_page(%options);
Return a L<Linkspace::Page> based on the sheet data.
=cut

#XXX This may need to move to Document, when searches cross sheets

sub get_page($)
{   my ($self, %args) = @_;
    my $views = $self->views;

    $args{view_limits} =  #XXX views or view_limits?
       [ map $views->view($_->view_id), $views->limits_for_user ];

    my $view_limit_extra_id
      = $self->user_can('view_limit_extra')
      ? $args{view_limit_extra_id}
      : $self->default_view_limit_extra_id;

    $args{view_limit_extra} = $views->view($view_limit_extra_id);

    $self->data->search(%args);
}

#----------------------
=head1 METHODS: MetricGroup administration

sub metric_group {...}
sub metric_group_create { $metric_group->import_hash($mg) }
=cut

#---------------------
=head1 METHODS: Topic administration

XXX Move to a separate sub-class?
=cut

has _topics_index => (
    is      => 'lazy',
    builder => sub {
        my $topics = Linkspace::Topic->search_objects({sheet => $_[0]});
        index_by_id $topics;
    },
);

sub has_topics() { keys %{$_[0]->_topics_index} }

sub topic($)
{   my ($self, $id) = @_;
    $self->_topics_index->{$id};
}

#XXX apparently double names can exist :-(  See import
sub topics_by_name($)
{   my $self = shift;
    my $name = lc shift;
    [ grep lc($_->name) eq $name, %{$self->_topics_index} ];
}

sub all_topics { [ values %{$_[0]->_topics_index} ] }

sub topic_create($)
{   my ($self, $insert) = @_;
    my $topic = Linkspace::Topic->create($insert);
    $self->_topic_index->{$topic->id} = $topic;
}

sub topic_update($%)
{   my ($self, $topic, $update) = @_;
    $topic->report_changes($update);
    $topic->update($update);
    $self;
}

sub topic_delete($)
{   my ($self, $topic) = @_;
    $self->layout->topic_unuse($topic);
    $topic->delete;
}

#----------------------
=head1 METHODS: Visualization
=cut

sub hide_blanks { ! $_[0]->sheet->no_hide_blank }

#----------------------
=head1 METHODS: Other

=head2 $sheet->column_unuse($column);
Remove all uses for the column in this sheet (and managing objects);
=cut

sub column_unuse($)
{   my ($self, $column) = @_;
    my $col_id = $column->id;
    $::db->update(Instance => { sort_layout_id => $col_id }, {sort_layout_id => undef});

    $self->layout->column_unuse($column);
    $self->views->column_unuse($column);
}

=head2 \%h = $self->default_sort;
Returns a HASH which contains the default values to sort row displays.  It returns
a HASH with a column C<id> and a direction (C<type>).
=cut

sub default_sort()
{   my $self = shift;
    my $col_id = $self->sort_column_id || $self->layout->column('_id');

     +{ id   => $col_id,
        type => $self->sort_type || 'asc',
      };
}

1;
