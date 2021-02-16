## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Test::Sheet;

use strict;
use warnings;
use utf8;

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
my @default_column_types =  qw/string intgr enum tree date daterange file person curval/;  # rag calc
my @default_enumvals     = qw/foo1 foo2 foo3/;

my @default_trees    =
  ( { text => 'tree1' },
    { text => 'tree2', children => [ { text => 'tree3' } ] },
  );

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
        person1    => undef,  # can only be filled runtime
    },
    {
        string1    => 'Bar',
        integer1   => 99,
        date1      => '2009-01-02',
        enum1      => 'foo2',
        daterange1 => ['2008-05-04', '2008-07-14'],
        person1    => undef,  # can only be filled runtime
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
    if(my $mv = delete $args->{multivalue_columns})
    {   foreach my $type (@$mv)
        {   Linkspace::Column->type2class($type)->can_multivalue or panic $type;
            $mv{$type} = 1;
        }
    }

    my $cc = delete $args->{column_count} || {};

    my $all_optional = exists $args->{all_optional} ? $args->{all_optional} : 1;

    my $curval_columns;
    if(my $c = delete $args->{curval_columns} || delete $args->{curval_column})
    {   $curval_columns = ref $c eq 'ARRAY' ? $c : [ $c ];
    }
    elsif(my $curval_sheet = delete $args->{curval_sheet})
    {   $curval_columns = [ grep ! $_->is_internal && !$_->type eq 'autocur',
           @{$curval_sheet->all_columns} ];
    }

    my $rag_code  = delete $args->{rag_code};
    my $calc_rt   = delete $args->{calc_return_type};
    my $calc_code = delete $args->{calc_code};

    foreach my $type (@$column_types)
    {   my $ref = $type eq 'intgr' ? 'integer' : $type;   # Grrrr

        foreach my $count (1.. ($cc->{$ref} || $cc->{$type} || 1))
        {
            my %insert = (
                type          => $type,
                name          => 'L' . $sheet_id . $ref . $count,
                name_short    => $ref . $count,
                is_optional   => $all_optional,
                is_multivalue => $mv{$type},
                permissions   => $permissions,
            );

            if($type eq 'enum')
            {   $insert{enumvals}   = \@default_enumvals;
            }
            elsif($type eq 'tree')
            {   $insert{tree}       = \@default_trees;
            }
            elsif($type eq 'curval')
            {   $insert{curval_columns} = $curval_columns;
            }
            elsif($type eq 'rag')
            {   $insert{code}        = $rag_code || _default_rag_code($sheet_id);
next;
            }
            elsif($type eq 'calc')
            {   $insert{return_type} = $calc_rt   || 'integer';
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

        local $row_data->{file1} = \%dummy_file_data
            if exists $row_data->{file1} && ref $row_data->{file1} ne 'HASH';

        local $row_data->{person1} ||= $::session->user
            if exists $row_data->{person1};

        my $revision = $row->revision_create({ cells => $row_data });
    }

    1;
}

# Add an autocur column to this sheet    XXX should not be used anymore
my $autocur_count = 50;
sub add_autocur
{   my ($self, $seqnr, $config) = @_;
    my $layout = $self->layout;

    my $autocur_columns = $config->{curval_columns}
        || $layout->columns_search({ internal => 0 });

    my $permissions = $config->{no_groups} ? undef :
      [ $self->group => $self->default_permissions ];

    my $name = 'autocur' . $autocur_count++;
    $layout->column_create({
        type            => 'autocur',
        name            => $name,
        name_short      => "L${seqnr}$name",
        curval_columns  => $autocur_columns,
        related_column  => $config->{related_column},
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

=head2 my $text =  $sheet->debug(%options);
With option C<show_internal> (default true) you can disable the display
of the internal columns.  You may use C<show_header> (default true)
and C<show_layout> (default false), C<show_revisions> (default false)
to control which components are shown.  With C<all> set to true, you
make sure all components are shown.

=cut

sub debug(%)
{   my ($self, %config) = @_;
    my $layout    = $self->layout;
    my $content   = $self->content;

    my $show_all  = $config{all};
    my $show_hist = $show_all || $config{show_history};
    my $max_width = $config{max_column_width} // 16;

    # We do not want to include the row-id and rev-id when the output is locked in a test
    my $show_rowid= exists $config{show_rowid} ? $config{show_rowid} : 1;
    my $show_revid= exists $config{show_revid} ? $config{show_revid} : 1;

    my $nr_intern = @{$layout->internal_columns_show_names};
    my $nr_data   = @{$layout->all_columns} - $nr_intern;
    my $row_ids   = $content->row_ids;

    my $columns   = $config{colums};
    if($show_all || $config{show_internal})
    {   $columns = $layout->all_columns;
    }
    else
    {   $columns = $layout->columns_search(exclude_internal => 1);
        unshift @$columns, $layout->column('_id') if $show_revid;
    }
    my @col_ids   = map $_->id, @$columns;

    my $short     = $self->name eq $self->name_short ? '' : " (".$self->name_short.")";
    my @out = sprintf "Sheet %d=%s%s, %d rows with %d data columns\n",
        $self->id, $self->name, $short, scalar @$row_ids, $nr_data
        if $show_all || (exists $config{show_header} ? $config{show_header} : 1);

    push @out, $layout->as_string(columns => $columns)
        if $show_all || $config{show_layout};

    my %col_width   = map +($_ => 2), @col_ids;
    my $rowid_width = 5;  # 'rowid'
    my @lines;

    foreach my $row_id (@$row_ids)
    {   my $row  = $content->row($row_id) or panic $row_id;
        my @revs = $show_hist ? @{$row->all_revisions} : $row->current;
        my @block;
        foreach my $revision (@revs)
        {   my @rev;
            if($show_rowid)
            {   my $lead = ! $show_hist ? '' : $revision->is_current ? '*' : ' ';
                push @rev, $lead . (@block ? '' : $row_id);
                $rowid_width = length $rev[-1] if length $rev[-1] > $rowid_width;
            }
     
            foreach my $col_id (@col_ids)
            {   my $val = $revision->cell($col_id)->as_string // '<undef>';
                substr($val, $max_width-1) = '⋮' if $max_width && length $val > $max_width;
                push @rev, $val;
                $col_width{$col_id} = length $val if length $val > $col_width{$col_id};
            }
            push @block, \@rev;
        }
        push @lines, @block;
    }

    if(@lines)
    {   my $format = '|' . join('|', map " \%-$col_width{$_}s ", @col_ids) . "|\n";
        my @header = map $_->position, @$columns;
        if($show_rowid)
        {   $format    = "| %-${rowid_width}s $format" if $show_rowid;
            unshift @header, 'rowid';
        }
        push @out, sprintf +($format =~ s/\|/=/gr), @header;
        push @out, sprintf $format, @$_ for @lines;
    }

    join '', @out;
}

=head2 my $cell = $sheet->cell($row, $column);
Returns the cell which is in the sheet on C<$row> (might be row object or row by object
or row_id) in the C<$column> (by object or name).

We probably do not need this in the normal sheet, but testing is seriously simplified
with this method.
=cut

sub cell($$)
{   my $self = shift;
    my $row    = $self->content->row(shift)   or return;
    my $column = $self->layout->column(shift) or return;
    $row->current->cell($column);
}

=head2 my $row_id = $sheet->row_at($serial);
Useful for testing only, especially to create values for the curval columns.
=cut

sub row_at($) { $_[0]->content->row_by_serial($_[1]) }

1;

