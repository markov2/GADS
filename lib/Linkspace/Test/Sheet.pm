## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Test::Sheet;

use strict;
use warnings;
 
use Log::Report  'linkspace';

use Linkspace::Column ();

use Moo;
extends 'Linkspace::Sheet';

sub _sheet_create($%)
{   my ($class, $config, %args) = @_;

    # By default no permission checking
    $args{allow_everything} = 1 unless exists $args{allow_everything};

    my $self = $class->SUPER::_sheet_create({
          name => delete $config->{name},
       },
       %args,
    );
    $self->_fill_layout($config);
    $self->_fill_content($config);

    panic $_ for keys %$config;
    $self;
}

# Not autocur
#my @default_column_types =  qw/string intgr enum tree date daterange file person curval rag/;
my @default_column_types =  qw/string intgr enum tree date daterange file person/;
my @default_enumvals     = qw/foo1 foo2 foo3/;

my @default_trees    =
  ( { text => 'tree1' },
    { text => 'tree2', children => [ { text => 'tree3' } ] },
  );

my @can_multivalue_columns = qw/calc curval date daterange enum file string tree/;
my @default_permissions    = qw/read write_new write_existing write_new_no_approval
    write_existing_no_approval/;

my %dummy_file_data = (
    name     => 'myfile.txt',
    mimetype => 'text/plain',
    content  => 'My text file',
);

sub _default_rag_code($) { my $seqnr = shift; <<__RAG }
function evaluate (L${seqnr}daterange1)
    if type(L${seqnr}daterange1) == "table" and L${seqnr}daterange1[1] then
        dr1 = L${seqnr}daterange1[1]
    elseif type(L${seqnr}daterange1) == "table" and next(L${seqnr}daterange1) == nil then
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
    if type(L${seqnr}daterange1) == "table" and L${seqnr}daterange1[1] then
        dr1 = L${seqnr}daterange1[1]
    elseif type(L${seqnr}daterange1) == "table" and next(L${seqnr}daterange1) == nil then
        dr1 = nil
    else
        dr1 = L${seqnr}daterange1
    end
    if dr1 == null then return end
    return dr1.from.year
end
__CALC

my @default_sheet_rows = (   # Don't change these: many tests depend on them
    {   string1    => 'Foo',
        integer1   => 50,
        date1      => '2014-10-10',
        enum1      => 'foo1',
        daterange1 => ['2012-02-10', '2013-06-15'],
    },
    {
        string1    => 'Bar',
        integer1   => 99,
        date1      => '2009-01-02',
        enum1      => 'foo2',
        daterange1 => ['2008-05-04', '2008-07-14'],
    },
);

sub _fill_layout($$)
{   my ($self, $args) = @_;
    my $layout   = $self->layout;
    my $sheet_id = $self->id;

    my $permissions = [ test_group => \@default_permissions ];

    # Restrict the columns to be created
    my $column_types = delete $args->{columns} || \@default_column_types;
    Linkspace::Column->type2class($_) or panic "Unsupported column type $_"
        for @$column_types;

    my %mv;
    if(my $mv = $args->{multivalue_columns})
    {   foreach my $type (@$mv)
        {   Linkspace::Column->type2class($mv)->can_multivalue or panic $mv;
            $mv{$type} = 1;
        }
    }

    my $cc = delete $args->{column_count} || {};

    my $all_optional = exists $args->{all_optional} ? $args->{all_optional} : 1;

    my ($curval_sheet, @curval_columns);
    if($curval_sheet = $args->{curval_sheet})
    {   if(my $cols = $args->{curval_columns})
        {   @curval_columns = @{$curval_sheet->layout->columns($cols)};
        }
        else
        {   @curval_columns = grep ! $_->is_internal && !$_->type eq 'autocur',
                @{$curval_sheet->all_columns};
        }
    }

    my $rag_code  = delete $args->{rag_code};
    my $calc_rt   = delete $args->{calc_return_type};
    my $calc_code = delete $args->{calc_code};

    foreach my $type (@$column_types)
    {
        foreach my $count (1.. ($cc->{$type} || 1))
        {   my $ref = $type eq 'intgr' ? 'integer' : $type;   # Grrrr

            my %insert = (
                type          => $type,
                name          => 'L' . $sheet_id . $ref . $count,
                name_short    => $ref . $count,
                is_optional   => $all_optional,
                is_multivalue => $mv{$type},
                permissions   => $permissions,
            );

            if($type eq 'enum')
            {   $insert{enumvals} = \@default_enumvals;
            }
            elsif($type eq 'tree')
            {   $insert{tree}     = \@default_trees;
            }
            elsif($type eq 'curval')
            {   $insert{refers_to_sheet} = $curval_sheet;
                $insert{curval_columns}  = \@curval_columns;
next;
            }
            elsif($type eq 'rag')
            {   $insert{code} = $rag_code || _default_rag_code($sheet_id);
next;
            }
            elsif($type eq 'calc')
            {   $insert{return_type} = $calc_rt || 'integer';
                $insert{code}        = $calc_code || _default_calc_code($sheet_id);
next;
            }

            $layout->column_create(\%insert);
        }
    }
}

sub _fill_content($$)
{   my ($sheet, $config) = @_;
    my $content = $sheet->content;
    my $data    = delete $config->{rows};

    unless($data)
    {   my @colnames = map $_->name_short, @{$sheet->layout->columns_search(userinput => 1)};
        foreach my $raw_data (@default_sheet_rows)
        {   my %row; @row{@colnames} = @{$raw_data}{@colnames};
            push @$data, \%row;
        }
    }

    foreach my $row_data (@$data)
    {   my $row = $content->row_create({
#           base_url => undef,   #XXX
        });

        $row_data->{file1} = \%dummy_file_data
            if exists $row_data->{file1} && ref $row_data->{file1} ne 'HASH';

        my $revision = $row->revision_create({ cells => $row_data });
    }

    1;
}

# Add an autocur column to this sheet    XXX should not be used anymore
my $autocur_count = 50;
sub add_autocur
{   my ($self, $seqnr, $config) = @_;
    my $layout = $self->layout;

    my $autocur_fields = $config->{curval_columns}
        || $layout->columns_search({ internal => 0 });

    my $permissions = $config->{no_groups} ? undef :
      [ $self->group => $self->default_permissions ];

    my $name = 'autocur' . $autocur_count++;
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


sub set_multivalue
{   my ($self, $config) = @_;
    my $layout = $self->layout;

    foreach my $col ($layout->columns_search(exclude_internal => 1))
    {   $layout->column_update($col, { is_multivalue => $config->{$col->type} })
            if exists $config->{$col->type};
    }
}

1;

