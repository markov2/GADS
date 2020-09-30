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
 
package Linkspace::Test::Sheet;

use strict;
use warnings;
 
use Log::Report  'linkspace';

use Moo;
extends 'Linkspace::Sheet';

has no_groups => (
    is      => 'ro',
    default => 0,
);

has organisation => (
    is => 'lazy',
    builder => sub { $::db->create(Organisation => { name => 'My Organisation' });
}

has department => (
    is => 'lazy',
    builder => sub { $::db->create(Department => { name => 'My Department' }) },
}

sub _build__users
{   my $self = shift;
    # If the site_id is defined, then we may be cresating multiple sites.
    # Therefore, offset the ID with the number of sites, to account that the
    # row IDs may already have been used.  This assumes that when testing
    # multiple sites that only the default 5 users are created.
    my $return; my $count = $self->schema->site_id && ($self->schema->site_id - 1) * 5;
    foreach my $permission (@{$self->users_to_create})
    {
        $count++;
        # Give view create permission as default, so that normal user can
        # create views for tests
        my $perms
            = $permission =~ 'normal'     ? ['view_create']
            : $permission eq 'superadmin' ? [qw/superadmin link delete purge view_group/]
            : [ $permission ];
        $return->{$permission} = $self->create_user(permissions => $perms, user_id => $count);
    }
    $return;
}

sub create_user
{   my ($self, %options) = @_;
    my @permissions = @{$options{permissions} || []};

    foreach my $permission (@permissions)
    {
        if (my $permission_id = $self->_permissions->{$permission})
        {
            $self->schema->resultset('UserPermission')->find_or_create({
                user_id       => $user_id,
                permission_id => $permission_id,
            });
            $user->clear_permission;
        }
        elsif (!$self->no_groups) {
            # Create a group for each user/permission
            my $name  = "${permission}_$user_id";
            my $group = $::db->get_record(Group => { name => $name });
               ||= $::db->create(Group => { name => $name });
}

has curval => (
    is => 'ro',
);

has curval_field_ids => (
    is => 'ro',
);

my $default_enumvals = qw/foo1 foo3 foo3/;

my @default_trees    =
  ( { text => 'tree1' },
    { text => 'tree2', children => [ { text => 'tree3' } ] },
  );

my @can_multivalue_columns = qw/calc curval date daterange enum file string tree/;
my @default_permissions = qw/read write_new write_existing write_new_no_approval
    write_existing_no_approval/;

my %dummy_file_data = (
    name     => 'myfile.txt',
    mimetype => 'text/plain',
    content  => 'My text file',
);

sub _default_rag_code($) { my $seqnr = shift; <<__RAG }
function evaluate (L${seqnr}daterange1)
    if type(L${seqnr}daterange1) == \"table\" and L${seqnr}daterange1[1] then
        dr1 = L${seqnr}daterange1[1]
    elseif type(L${seqnr}daterange1) == \"table\" and next(L${seqnr}daterange1) == nil then
        dr1 = nil
    else
        dr1 = L${seqnr}daterange1
    end
    if dr1 == nil then return end
    if dr1.from.year < 2012 then return 'red' end
    if dr1.from.year == 2012 then return 'amber' end
    if dr1.from.year > 2012 then return 'green' end
end
__RAG

sub _default_calc_code($) { my $seqnr = shift;  <<__CALC }
function evaluate (L${seqnr}daterange1)
    if type(L${seqnr}daterange1) == \"table\" and L${seqnr}daterange1[1] then
        dr1 = L${seqnr}daterange1[1]
    elseif type(L${seqnr}daterange1) == \"table\" and next(L${seqnr}daterange1) == nil then
        dr1 = nil
    else
        dr1 = L${seqnr}daterange1
    end
    if dr1 == null then return end
    return dr1.from.year
end
__CALC

my @default_sheet_rows = (   # Don't change these: some tests depend on them
    {   string1    => 'Foo',
        integer1   => 50,
        date1      => '2014-10-10',
        enum1      => 1 + $config->{curval_offset},
        daterange1 => ['2012-02-10', '2013-06-15'],
    },
    {
        string1    => 'Bar',
        integer1   => 99,
        date1      => '2009-01-02',
        enum1      => 2 + $config->{curval_offset},
        daterange1 => ['2008-05-04', '2008-07-14'],
    },
);

sub _create_content($%)
{   my ($self, %args) = @_;
    my $content = $self->content;
    my $sheet_id = $self->id;

#   my $permissions = $self->no_groups ? undef
#     : { $self->group->id => $self->default_permissions };

    my $mv = delete $args{multivalue_columns}
          || (delete $args{multivalues} ? \@can_multivalue_columns : ());

    my %mv = map +($_ => 1), @$mv;

    my $cc = column_count

   my $all_optional = exists $args{all_optional} ? $args{all_optional} : 1;
   my $calc_return_type = $args{calc_return_type} || 'integer';


curval --> curval_sheet
    my $curval_offset = $curval_sheet ? 6 : 0;
    # curval_fields_ids --> curval_columns, names relative to curval_sheet
    my $curval_columns = $curval_sheet->layout->columns($args{curval_columns});

    foreach my $type ( qw/string intgr enums tree/ )
# date daterange file person
    {
        foreach my $count (1.. ($column_count{$type} || 1))
        {
            my %insert = (
                type          => $type,
                name          => $type . $count,
                name_short    => 'L' . $sheet_id . $type . $count,
                is_optional   => $all_optional,
                is_multivalue => $mv{$type},
                permissions   => $permissions,
            );

            if($type eq 'enum')
            {    $insert{enumvals} = \@default_enumvals;
            }
            elsif($type eq 'tree')
            {    $insert{tree}     = \@default_trees;
            }
            $layout->column_create($insert);
        }
    }


my $file1 = $layout->column_create(
    type          => 'file',
    name          => 'file1',
    optional      => $self->optional,
    is_multivalue => $self->multivalue && $self->multivalue_columns->{file},
    permissions   => $permissions,
);

my $person1 = $layout->column_create(
    type          => 'person',
    name          => 'person1',
    permissions   => $permissions,
);

    my @curvals;
    if ($self->curval)
    {
        foreach my $count (1..($self->column_count->{curval} || 1))
        {
            my $refers_to_sheet = $config->{curval_sheet};
            my $curval_field_ids_rs = $::db->search(Layout => {
                type        => { '!=' => 'autocur' },
                internal    => 0,
                instance_id => $refers_to_sheet->id,
            });
            my $curval_fields = $config->{curval_fields} ||
                [ map $_->id, $curval_field_ids_rs->all ];

my $name = 'curval'.$count;
my $curval = $layout->column_create(
    type          => 'curval',
    name          => $name,
    name_short    => "L${instance_id}$name",
    optional      => $config->{optional},
    is_multivalue => $self->multivalue && $self->multivalue_columns->{file},  #XXX file?
    permissions   => $permissions,
    refers_to_instance_id => $refers_to_instance_id,
    curval_field_ids => $curval_field_ids.
);
            push @curvals, $curval;
        }
    }

my $rag1 = $layout->column_create(
    type          => 'rag',
    name          => 'rag1',
    optional      => $self->optional,
    permissions   => $permissions,
    code          => $args{rag_code} || _default_rag_code($sheet->id);
);

my $calc1 = $layout->column_create(
    type        => 'calc',
    name        => 'calc1',
    name_short  => "L${instance_id}calc1",
    return_type => $self->calc_return_type,
    code        => $args{calc_code} || _default_calc_code($sheet->id);
    permissions => $permissions,
    is_multivalue => $self->multivalue && $self->multivalue_columns->{calc},
);

# Add an autocur column to this sheet
my $autocur_count = 50;
sub add_autocur
{   my ($self, $seqnr, $config) = @_;

    my $autocur_fields = $config->{curval_columns}
        || $layout->columns_search({ internal => 0 });

    my $permissions = $config->{no_groups} ? undef :
      [ $self->group => $self->default_permissions ];

    my $name = 'autocur' . $autocur_count++,
    $layout->column_create({
        type            => 'autocur',
        name            => $name,
        name_short      => "L${seqnr}$name",
        refers_to_sheet => $config->{refers_to_sheet},
        curval_fields   => $autocur_fields,
        related_field   => $config->{related_field},
        permissions     => $permissions,
    });
}

sub 
    my $sheet = make _sheet...
    _sheet_layout($sheet, $config);
    _sheet_fill($sheet, $config);

sub sheet_layout($$)
{   my ($sheet, $config) = @_;
    my $cc    = $config->{column_count} || {};
    my $is_mv = $config->{multivalue_columns} || $default_multivalue_columns;
    $is_mv = map +($_ => 1) @$is_mv if ref $is_mv eq 'ARRAY';

    #XXX to be removed after conversion of tests
    panic "Rename curval => curval_sheet" if $config->{curval};
    panic "Rename curval_field_ids => curval_columns" if $config->{curval_field_ids};

    if(my $curval_sheet = $config->{curval_sheet})
    {   my $columns = $curval_sheet->layout->columns($config->{curval_columns});
        ...;
    }
}

sub fill_sheet($$)
{   my ($sheet, $config) = @_;
    my $content = $sheet->content;

    my $data = $config->{data} || \@default_sheet_rows;
    $#$data  = $config->{rows} if defined $config->{rows};

    foreach my $row_data (@$data)
    {   my $row = $content->row_create({
            base_url => undef,
        });

        $row_data->{file1} = \%dummy_file_data
            if exists $row_data->{file1} && ref $row_data->{file1} ne 'HASH';

        my $revision = $row->revision_create($row_data, no_alerts => 1);
    }

    1;
};

sub set_multivalue
{   my ($self, $value) = @_;
    foreach my $col ($self->layout->all_columns)
    {   if($self->multivalue_columns->{$col->type})
        {   $layout->column_update($col, { is_multivalue => $value });
        }
    }
    $self->layout->clear;
}

1;

