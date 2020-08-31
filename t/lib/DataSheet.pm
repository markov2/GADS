package t::lib::DataSheet;

use strict;
use warnings;

use JSON qw(encode_json);
use Log::Report;
use Linkspace::Sheet::Layout;
use Moo;
use MooX::Types::MooseLike::Base qw(:all);

sub clear_not_data
{   my ($self, %options) = @_;
    foreach my $key (keys %options)
    {
        my $prop = "_set_$key";
        $self->$prop($options{$key});
    }

    # Need to first clear any autocur columns referring to this one. We'll
    # remember them, then put them back in after.
    # Find:
    my @related = $::db->search(Layout => {
        'me.instance_id'            => { '!=' => $sheet->id },
        'related_field.instance_id' => $sheet->id,
    },{
        join => 'related_field',
    })->all;

    # Remember:
    my %related;
    foreach my $related (@related)
    {
        $related{$related->id} = {
            related_to    => $related->related_field->name,
            curval_fields => [ map $_->child->name, $related->curval_fields_parents ],
        };
        # Clear:
        $related->update({ related_field => undef });
        $related->curval_fields_parents->delete;
    }

    $self->layout->purge;
    $self->clear_layout;
    $self->clear_columns;
    $self->create_records;

    # Return to previous:
    my $columns = $self->columns;
    foreach my $related_id (keys %related)
    {
        # Find curval it is related to
        my $f = $::db->search(Layout => {
            instance_id => $sheet->id,
            name        => $related{$related_id}->{related_to},
        })->next;

        # Find autocur field
        my $related = $::db->get_record(Layout => $related_id);
        $related->update({ related_field => $f->id });

        # Find and add related curval fields
        foreach my $child_name (@{$related{$related_id}->{curval_fields}})
        {
            my $f = $::db->search(Layout => (
                instance_id => $self->layout->instance_id,
                name        => $child_name,
            })->next
                or next; # Skip if no longer exists - may have been additional temporary column
            $::db->create(CurvalField => {
                parent_id => $related_id,
                child_id  => $f->id,
            });
        }
    }
}

has curval_offset => (
   is  => 'lazy',
   isa => Int,
);

sub _build_curval_offset
{   my $self = shift;
    $self->curval ? 6 : 0;
}

has no_groups => (
    is      => 'ro',
    isa     => Bool,
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
    my $instance_id = $options{instance_id} || $self->instance_id;
    my $user_id     = $options{user_id};

    $user->update({
        username      => "user$user_id\@example.com",
        email         => "user$user_id\@example.com",
        firstname     => "User$user_id",
        surname       => "User$user_id",
        value         => "User$user_id, User$user_id",
        organisation  => $self->organisation->id,
        department_id => $self->department->id,
    });

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

has columns => (
    is      => 'ro',
    lazy    => 1,
    clearer => 1,
    builder => sub {
        my $self = shift;
        $self->__build_columns;
    },
);

# Whether to create multiple columns of a particular type

has curval => (
    is => 'ro',
);

has curval_field_ids => (
    is => 'ro',
);

has calc_return_type => (
    is      => 'ro',
    isa     => Str,
    default => 'integer',
);

has multivalue => (
    is      => 'rwp',
    default => 0,
);

has multivalue_columns => (
    is      => 'rw',
    builder => sub {
        +{
            curval    => 1,
            enum      => 1,
            tree      => 1,
            file      => 1,
            date      => 1,
            daterange => 1,
            string    => 1,
            calc      => 1,
        };
    },
);

# Whether columns should be optional
has optional => (
    is      => 'ro',
    default => 1,
);

has user_permission_override => (
    is      => 'ro',
    default => 1,
);

has config => (
    is => 'lazy',
);

sub _build_config
{   my $self = shift;
    GADS::Config->instance;
}

has default_permissions => (
    is      => 'ro',
    isa     => ArrayRef,
    default => sub {
        [qw/read write_new write_existing write_new_no_approval write_existing_no_approval/]
    },
);

# Exact name of _build_columns causes recursive loop in Moo...
sub __build_columns
{   my $self = shift;

    my $schema      = $self->schema;
    my $layout      = $self->layout;
    my $instance_id = $self->instance_id;
    my $permissions = $self->no_groups ? undef
      : { $self->group->id => $self->default_permissions };

    my $columns = {};

    my @strings;
    foreach my $count (1..($self->column_count->{string} || 1))
    {
my $string = $layout->create_column(
    optional      => $self->optional,
    type          => 'string',
    name          => "string$count",
    name_short    => "L${instance_id}string$count",
    is_multivalue => $self->multivalue && $self->multivalue_columns->{string},
    permissions   => $permissions,
);
        push @strings, $string;
    }

    my @integers;
    foreach my $count (1..($self->column_count->{integer} || 1))
    {
my $integer = $layout->create_column(
    optional      => $self->optional,
    type          => 'intgr',
    name          => "integer$count",
    name_short    => "L${instance_id}integer$count",
    is_multivalue => $self->multivalue && $self->multivalue_columns->{integer},
    permissions   => $permissions,
);
        push @integers, $integer;
    }

    my @enums;
    foreach my $count (1..($self->column_count->{enum} || 1))
    {
my $enum = $layout->create_column(
    optional      => $self->optional,
    type          => 'enum',
    name          => "enum$count",
    name_short    => "L${instance_id}enum$count",
    is_multivalue => $self->multivalue && $self->multivalue_columns->{enum},
    permissions   => $permissions,
    enumvals      => [
        { value => 'foo1' },
        { value => 'foo2' },
        { value => 'foo3' },
    ],
);
        push @enums, $enum;
    }

    my @trees;
    foreach my $count (1..($self->column_count->{tree} || 1))
    {
my $tree = $layout->create_column(
    type          => 'tree',
    name          => "tree$count",
    name_short    => "L${instance_id}tree$count",
    optional      => $self->optional,
    is_multivalue => $self->multivalue && $self->multivalue_columns->{tree},
    permissions   => $permissions,
);
#XXX
        $tree->update([{
            children => [],
            data     => {},
            text     => 'tree1',
            id       => 'j1_1',
        },
        {
            data     => {},
            text     => 'tree2',
            children => [
                {
                    data     => {},
                    text     => 'tree3',
                    children => [],
                    id       => 'j1_3'
                },
            ],
            id       => 'j1_2',
        }]);

        push @trees, $tree;
    }

    my @dates;
    foreach my $count (1..($self->column_count->{date} || 1))
    {
my $date = $layout->create_column(
    type          => 'date',
    name          => "date$count",
    name_short    => "L${instance_id}date$count",
    optional      => $self->optional,
    is_multivalue => $self->multivalue && $self->multivalue_columns->{date},
    permissions   => $permissions,
);

        push @dates, $date;
    }

    my @dateranges;
    foreach my $count (1..($self->column_count->{date} || 1))
    {
my $daterange = $layout->create_column(
    type          => 'daterange',
    name          => "daterange$count",
    name_short    => "L${instance_id}daterange$count",
    optional      => $self->optional,
    is_multivalue => $self->multivalue && $self->multivalue_columns->{daterange},
    permissions   => $permissions,
);

        push @dateranges, $daterange;
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

    # At this point, layout will have been built with current columns (it will
    # have been built as part of creating the RAG column). Therefore, clear it,
    # but keep the same reference in this object for code that has already taken
    # a reference to the old one.
    $self->layout->clear;

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

# Convert a filter from column names to ids (as required to use)
sub convert_filter
{   my ($self, $filter) = @_;
    $filter or return;
    my %new_filter = %$filter; # Copy to prevent changing original
    $new_filter{rules} = []; # Make sure not using original ref in new

    foreach my $rule (@{$filter->{rules}})
    {
        next unless $rule->{name};
        # Copy again
        my %new_rule = %$rule;
        my @colnames = split /\_/, delete $new_rule{name};
        my @colids = map { /^[0-9]+/ ? $_ : $self->columns->{$_}->id } @colnames;
        $new_rule{id} = join '_', @colids;
        push @{$new_filter{rules}}, \%new_rule;
    }
    \%new_filter;
}

# Can be called during debugging to dump data table. Results to be expanded
# when required.
sub dump_data
{   my $self = shift;
    foreach my $current ($::db->search(Current => {
        instance_id => $self->layout->instance_id,
    })->all)
    {
        print $current->id.': ';
        my $record_id = $::db->search(Record => { current_id => $current->id })
            ->get_column('id')->max;

        foreach my $ct (qw/tree1 enum1/)
        {
            my $v = $::db->search(Enum => {
                record_id => $record_id,
                layout_id => $self->columns->{$ct}->id,
            })->next;
            my $val = $v->value && $v->value->value || '';
            print "$ct ($val) ";
        }
        print "\n";
    }
}

1;

