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

package Linkspace::Sheet::Approval;

use GADS::Datum::Person;
use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw(:all);

has sheet => (
    is       => 'ro',
    required => 1,
    weakref  => 1,
);

has records => (
    is      => 'lazy',
    builder => sub { [values %{$self->_records} ] },
);

has count => (
    is      => 'lazy',
    builder => sub { scalar keys %{$_[0]->_records} },
);

has _records => (
    is  => 'lazy',
    isa => HashRef,
);

sub _build__records
{   my $self = shift;
    my $user = $::session->user;

    # First short-cut and see if it is worth continuing
    return {} unless $::db->search(Record => {
        approval              => 1,
        'current.instance_id' => $sheet->id,
    }, {
        join => 'current',
    })->count;

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

    my $datum_tables = $sheet->layout->datum_tables;
    if($sheet->user_can('approve_new'))
    {
        my %search = (
            'current.instance_id'      => $sheet->id;
            'record.approval'          => 1,
            'layout_groups.permission' => 'approve_new',
            'user_id'                  => $user->id,
            'record_previous.id'       => undef,
        );
    
        push @hits, $::db->search($_ => \%search, $options)->all
            for @$datum_tables;
    }

    if($sheet->user_can('approve_existing'))
    {   my %search = (
            'current.instance_id'      => $sheet->id,
            'record.approval'          => 1,
            'layout_groups.permission' => 'approve_existing',
            'user_id'                  => $user->id,
            'record_previous.id'       => { '!=' => undef },
        );

        push @hits, $::db->search($_ => \%search, $options)->all
            for @$datum_tables;
    }

    my %records;

    foreach my $hit (@hits)
    {   my $record_id = $hit->{record}->{id};

        $records->{$record_id} ||= {
            record_id  => $record_id,
            current_id => $hit->{record}->{current_id},
            createdby  => GADS::Datum::Person->new(
                record_id => $record_id,
                set_value => { value => $hit->{createdby} },
            ),
        };
    }

    \%records;
}

1;

