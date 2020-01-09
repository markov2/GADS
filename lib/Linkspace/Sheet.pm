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

use Algorithm::Dependency::Source::HoA ();
use Algorithm::Dependency::Ordered ();

=head1 NAME
Linkspace::Sheet - manages one sheet: one table with a Layout

=head1 SYNOPSIS

  my $doc = $::session->site->document;
  my @sheets = $doc->all_sheets;

=head1 DESCRIPTION

=head1 METHODS: Constructors

=head2 my $sheet = Linkspace::Sheet->new(%options);
=cut

=head2 my $sheet = Linkspace::Sheet->from_record($record, %options);
=cut

sub from_record
{   my ($class, $record, %args) = @_;
    $class->new( { %$record, %args } );
}

=head2 my $new = $sheet->update(\%changes, %options);
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
    );
}

=head1 METHODS: Accessors

=head2 my $doc = $sheet->document;
=cut

has document => (
    is       => 'ro',
    required => 1,
    weak_ref => 1,
);

=head2 my $layout = $sheet->layout;
=cut

has layout => (
    is => 'lazy',
    builder => sub {
        my $self = shift;
        $self->document->layout_for_sheet($self);
    },
);

=head1 METHODS: the sheet itself

=cut

=head2 $sheet->delete;
Remove the sheet.
=cut

sub delete($)
{   my $self     = shift;
    my $sheet_id = $self->id;

    my $guard = $::db->begin_work;

    $_->delete
       for $self->search_columns(only_internal => 1, include_hidden => 1);

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

    # Start with a clean sheet
    $class->from_id($sheet_id);
}

=head1 METHODS: Column management

=head2 \@cols = $sheet->columns;
=cut

has columns => (
    is    => 'lazy',
    isa   => ArrayRef,
    builder => sub {
        [ map Linkspace::Column->from_id($_), $_[0]->column_ids ]
    },
);

=head2 \@col_ids = $sheet->column_ids;
=cut

has column_ids => (
    is    => 'lazy',
    isa   => ArrayRef,
    builder => sub { $::session->site->document->columns_for_sheet($_[0]) },
}

=head2 $col = $sheet->column_by_id($id);
=cut

has _column_by_id => (
    is      => 'ro',
    isa     => HashRef,
    default => +{},
}

sub column_by_id($)
{   my ($self, $id) = @_;
    
}

=head2 \@cols = $sheet->search_columns(%options)
=cut

my %filters_invariant = (
    exclude_hidden   => sub { ! $_[0]->hidden },
    exclude_internal => sub { ! $_[0]->internal },
    only_internal    => sub {   $_[0]->internal },
    only_unique      => sub {   $_[0]->isunique },
    can_child        => sub {   $_[0]->can_child },
    linked           => sub {   $_[0]->link_parent },
    is_globe         => sub {   $_[0]->return_type eq 'globe' },
    has_cache        => sub {   $_[0]->has_cache },
    user_can_read    => sub {   $_[0]->user_can('read') },
    user_can_write   => sub {   $_[0]->user_can('write') },
    without_topic    => sub { ! $_[0]->topic_id },
    user_can_write_new          => sub { $_[0]->user_can('write_new') },
    user_can_write_existing     => sub { $_[0]->user_can('write_existing') },
    user_can_readwrite_existing =>
        sub { $_[0]->user_can('write_existing') || $_[0]->user_can('read') },
    user_can_approve_new        => sub { $_[0]->user_can('approve_new') },
    user_can_approve_existing   => sub { $_[0]->user_can('approve_existing') },
);

my %filters_compare = (
    type       => sub { $_[0]->type       eq $_[1] },
    remember   => sub { $_[0]->remember   == $_[1] },
    userinput  => sub { $_[0]->userinput  == $_[1] },
    multivalue => sub { $_[0]->multivalue == $_[1] },
    topic      => sub { $_[0]->topic_id   == $_[1] },
);

# Order the columns in the order that the calculated values depend
# on other columns
sub _order_dependencies
{   my ($self, @columns) = @_;
    @columns or return;

    my %deps  = map +($_->id => $_->dependencies), @columns;
    my $source = Algorithm::Dependency::Source::HoA->new(\%deps);
    my $dep    = Algorithm::Dependency::Ordered->new(source => $source)
        or die 'Failed to set up dependency algorithm';

    map $self->column_by_id($_), @{$dep->schedule_all};
}

sub search_columns
{   my ($self, %options) = @_;

    # Some parameters are a bit inconvenient
    $options{exclude_hidden} = ! delete $options{include_hidden}
        if exists $options{include_hidden};

    if(exists $options{topic_id})
    {   if(my $topic = delete $options{topic_id})
             { $options{topic} = $topic }
        else { $options{without_topic} = 1 }
    }

    my @filters;
    foreach my $flag (keys %options)
    {
        if(my $f = $filters_invariant{$flag})
        {   # A simple filter, based on the layout alone
            push @filters, $f if $options{$flag};
        }
        elsif(my $g = $filters_compare{$flag})
        {   # Filter based on comparison
            if(defined(my $need = $options{$flag}))
            {   push @filters, sub { $g->($_[0], $need) };
            }
        }
    }

    my $filter
      = !@filters   ? sub { 1 }
      : @filters==1 ? $filters[0]
      : sub {
            my $v = shift;
            $_->($v) || return 0 for @filters;
            1;
        };

    my @columns  = grep $filter->($_), @{$self->columns};

    @columns = $self->_order_dependencies(@columns)
        if $options{order_dependencies};

    if($options{sort_by_topics})
    {
        # Sorting by topic involves keeping the order of fields that do not
        # have a defined topic, but slotting in those together that have the
        # same topic.

        # First build up an index of topics and their fields
        my %topics;
        foreach my $col (@columns)
        {   my $topic = $col->topic_id or next;
            push @{$topics{$topic}}, $col;
        }

        my @new; my $previous_topic_id = 0; my %done;
        foreach my $col (@columns)
        {
            next if $done{$col->id};
            $done{$col->id} = 1;
            if ($col->topic_id && $col->topic_id != $previous_topic_id)
            {   foreach (@{$topics{$col->topic_id}})
                {   push @new, $_;
                    $done{$_->id} = 1;
                }
            }
            else {
                push @new, $col;
                $done{$col->id} = 1;
            }
            $previous_topic_id = $col->topic_id || 0;
        }
        @columns = @new;
    }

    @columns;
}

1;
