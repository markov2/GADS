=pod
GADS - Globally Accessible Data Store
Copyright (C) 2014 Ctrl O Ltd

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

package Linkspace::Page::Current;

use Log::Report 'linkspace';

use Linkspace::Datum::Person  ();

sub db_table { 'Current' }

sub db_field_rename { +{
    deleted => 'is_deleted',
} };

### 2020-06-15: columns in GADS::Schema::Result::Current
# id           deleted      draftuser_id parent_id
# instance_id  deletedby    linked_id    serial

use Moo;
extends 'Linkspace::Page', 'Linkspace::DB::Table';

__PACKAGE__->db_accessors;

use namespace::clean;

=head1 NAME

Linkspace::Page::Current - the latest version of the sheet content

=head1 SYNOPSIS
  my $page = $sheet->content->current;

=head1 DESCRIPTION
This is the current status of the sheet.

B<Be aware> that sheets can be very large: processing must be as lazy as
possible.  A db-search on records is preferred over processing all records.

=head1 METHODS: constructors
=cut

#---------------
=head1 METHODS: Attributes
=cut

#---------------
=head1 METHODS: Approval

=head2 $page->wants_approval;
Returns a true value when any row of the sheet needs approval.
=cut

has wants_approval => (
    is      => 'lazy',
    builder => sub
    {   $::db->search(Current => {
            instance_id        => $self->sheet->id,
            "records.approval" => 1,
        },{
            join => 'records',
            rows => 1,
        })->next;
    }
);

=head2 \%info = $page->requires_approval($user?);
Returns a HASH which hash row_ids as key and some details as value, for each of
the rows where the C<$user> can
=cut

has _requires_approval => ( is => 'ro', default => sub { +{} } );

sub requires_approval(;$)
{   my $self = shift;
    my $user = shift || $::session->user;

    # First short-cut and see if it is worth continuing
    $self->wants_approval or return {};

    $self->_requires_approval->{$user->id} ||= $self->_create_approval_info($user);
}

sub _create_approval_info($)
{   my ($self, $user) = @_;
    my $sheet_id = $self->id;

    # Each hit contains two parts: some record columns and createdby info.
    my $options = {
        join => [
            {
                record => [
                    'current',
                    { record => ['record_previous', 'createdby'] },
                ],
            },
            {
                layout => {
                    layout_groups => { group => 'user_groups' },
                },
            },
        ],
        select => [
            { max => 'record.id' },
            { max => 'record.current_id' },
            { max => 'createdby.id' },
            { max => 'createdby.firstname' },
            { max => 'createdby.surname' },
            { max => 'createdby.email' },
            { max => 'createdby.freetext1' },
            { max => 'createdby.freetext2' },
            { max => 'createdby.value' },
        ],
        as => [qw/
            record.id
            record.current_id
            createdby.id
            createdby.firstname
            createdby.surname
            createdby.email
            createdby.freetext1
            createdby.freetext2
            createdby.value
        /],
        group_by => 'record.id',
        result_class => 'HASH',
    };

    my @hits;

    my $meta_tables = Linkspace::Column->meta_tables;
    if($sheet->user_can(approve_new => $user))
    {   my %search = (
            'current.instance_id'      => $sheet_id,
            'record.approval'          => 1,
            'layout_groups.permission' => 'approve_new',
            'user_id'                  => $user->id,
            'record_previous.id'       => undef,
        );
    
        push @hits, $::db->search($_ => \%search, $options)->all
            for @$meta_tables;
    }

    if($sheet->user_can(approve_existing => $user))
    {   my %search = (
            'current.instance_id'      => $sheet_id,
            'record.approval'          => 1,
            'layout_groups.permission' => 'approve_existing',
            'user_id'                  => $user->id,
            'record_previous.id'       => { '!=' => undef },
        );

        push @hits, $::db->search($_ => \%search, $options)->all
            for @$meta_tables;
    }

    my %records;

    foreach my $hit (@hits)
    {   my $record_id = $hit->{record}->{id};

        $records{$record_id} ||= +{
            record_id  => $record_id,
            current_id => $hit->{record}->{current_id},
            createdby  => Linkspace::Datum::Person->new(
                record_id => $record_id,
                set_value => { value => $hit->{createdby} },
            ),
        };
    }

    \%records;
}

sub row_current($@)
{   my ($self, $which) = (shift, shift);
    blessed $which ? $which : $self->from_id($which, @_);
}

sub row_delete
{   my ($self, $which) = @_;
    my $current = $self->row_current($which);

    $current->update({
        deleted   => DateTime->now,
        deletedby => $::session->user->id,
    });
}

# returns current_ids
sub child_ids($)
{   my ($self, $row) = @_;
    return [] if $row->has_parent;   # no multilevel parental relations

    my $children = $self->search_records({
        parent_id         => $row->current_id,
        'me.deleted'      => undef,
        'me.draftuser_id' => undef,
    });

    [ $children->get_column('id')->all ];
}

sub max_serial()
{   $self->search(Current => { instance_id => $sheet->id })
        ->get_column('serial')->max;
}

sub row_create($)
{   my ($self, $insert) = @_;
    $insert->{sheet} = $self->sheet;

    my $guard  = $::db->begin_work;
    $insert->{serial} = $self->max_serial + 1;
    my $current_id = $self->create($insert, sheet => $self->sheet);

    $guard->commit;
}

1;
