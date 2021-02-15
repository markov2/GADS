## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Sheet;

use Log::Report  'linkspace';
use Clone        'clone';
use Algorithm::Dependency::Source::HoA ();
use Algorithm::Dependency::Ordered ();

use Linkspace::Sheet::Layout   ();
use Linkspace::Sheet::Access   ();
use Linkspace::Sheet::Content ();
#use Linkspace::Sheet::Views   ();
#use Linkspace::Sheet::Graphs  ();
#use Linkspace::Sheet::Dashboards  ();

use Moo;
extends 'Linkspace::DB::Table';

###!!!!  The naming is confusing, because that's legacy.
###  table Instance      contains Sheet configuration
###  table InstanceGroup relates Sheets to Users
#XXX no_hide_blank cannot be changed

sub db_table { 'Instance' }

sub db_fields_unused { [ qw/no_overnight_update/ ] }

sub db_field_rename { +{
    sort_layout_id => 'sort_column_id',
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

around BUILDARGS => sub ($$%)
{   my ($orig, $class, %args) = @_;
    $args{site} ||= $args{document}->site;
    $class->$orig(%args);
};

sub _sheet_update($)
{   my ($self, $update) = @_;
    my $permissions = delete $update->{permissions};

    $self->_validate($update);
    $self->update($update);
    $self->access->set_permissions($permissions);
    $self;
}

sub _validate($)
{   my ($thing, $insert) = @_;
    my $slid = $insert->{sort_column_id};
    ! defined $slid || is_valid_id $slid
        or error __x"Invalid sheet sort_layout_id '{id}'", id => $slid;

    if(my $st = $insert->{sort_type})
    {   $st eq 'asc' || $st eq 'desc' || $st eq 'none'
            or error __x"Invalid sheet sort type {type}", type => $st;
    }

    $insert;
}

sub _sheet_delete($)
{   my $self     = shift;
    my $sheet_id = $self->id;

    $self->site->users->sheet_unuse($self);
    $self->layout->sheet_unuse;
    $self->access->sheet_unuse;
#   $self->dashboards->sheet_unuse;

    $self->delete;
}

sub _sheet_create($%)
{   my ($class, $insert, %args) = @_;
    my $doc = $args{document} or panic;

    my $permissions   = delete $insert->{permissions};
    $insert->{site}   = $doc->site;
    $insert->{name} ||= $insert->{short_name};
    $insert->{name_short} ||= $insert->{name};

    $class->_validate($insert);
    my $self = $class->create($insert, %args);
    $self->layout->insert_initial_columns;
    $self->access->set_permissions($permissions) if $permissions;
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

has allow_everything => (
    is       => 'rw',
    default  => sub { 0 },
);

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
=head1 METHODS: Sheet Content, Keeping records
Each Sheet has a Content object to maintain it's data.

=head2 my $content = $sheet->content(%options);
Returns a L<Linkspace::Sheet::Content> object.  When not a single option is given, it
will each time return the same object.  However, with some C<%option> (especially the
C<rewind>) it will return a dedicated object.
=cut

has _content => (
    is      => 'lazy',
    builder => sub { Linkspace::Sheet::Content->new(sheet => $_[0]) },
);

sub content(%)
{   my $self = shift;
    @_ ? Linkspace::Sheet::Content->new(sheet => $self, @_) : $self->_content;
}

#----------------------
=head1 METHODS: Sheet permissions

=head2 my $access = $sheet->access;
=cut

has access => (
    is      => 'lazy',
    builder => sub { Linkspace::Sheet::Access->new(sheet => $_[0]) },
);

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
    || $self->access->group_can($permission, $user->group)
    || $user->has_permission($permission);
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

    $self->content->search(%args);
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

### 2020-08-19: columns in GADS::Schema::Result::Topic
# id                    click_to_edit         prevent_edit_topic_id
# instance_id           description
# name                  initial_state
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
=head1 METHODS: Other

=head2 $sheet->column_unuse($column);
Remove all uses for the column in this sheet (and managing objects);
=cut

sub column_unuse($)
{   my ($self, $column) = @_;
    my $col_id = $column->id;
    $::db->update(Instance => { sort_layout_id => $col_id }, {sort_layout_id => undef});

    $self->layout->column_unuse($column);
#   $self->views->column_unuse($column);
}

=head2 \%h = $self->default_sort;
Returns a HASH which contains the default values to sort row displays.
It returns a HASH with a column C<id> and a direction (C<type>).
=cut

sub default_sort()
{   my $self = shift;
    my $col_id = $self->sort_column_id || $self->layout->column('_id');

     +{ id   => $col_id,
        type => $self->sort_type || 'asc',
      };
}

1;
