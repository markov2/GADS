## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Rag;

use Moo;
extends 'Linkspace::Column::Code';
with 'Linkspace::Role::Presentation::Column::Rag';

use Log::Report 'linkspace';

#----------- Helper tables
# The Rag table configures the column type.  The Ragval table contains
# the datums.
#
### 2020-09-03: columns in GADS::Schema::Result::Rag
# id         amber      code       green      layout_id  red
#
### 2020-09-03: columns in GADS::Schema::Result::Ragval
# id         value      layout_id  record_id

my @filter_values = (
    [  1, a_grey   => 'Grey'   , 'undefined' ],
    [  2, b_red    => 'Red'    , 'danger'    ],
    [  3, c_amber  => 'Amber'  , 'warning'   ],
    [  4, c_yellow => 'Yellow' , 'advisory'  ],
    [  5, d_green  => 'Green'  , 'success'   ],
    [ -1, e_purple => 'Purple' , 'unexpected'],
);

my %rag_id2string = map +($_->[0] => $_->[2]), @filter_values;
my %rag_id2grade  = map +($_->[0] => $_->[3]), @filter_values;
my %code2rag_id   = map +($_->[1] => $_->[0]), @filter_values;

###
### META
###

INIT { __PACKAGE__->register_type }

sub value_table   { 'Ragval' }
sub has_fixedvals { 1 }
sub form_extras   { [ qw/code_rag no_alerts_rag no_cache_update_rag/ ], [] }

### for Rag presentation only

sub _filter_values { [ map +[ $_->[1] => $_->[2] ], @filter_values ] }
sub as_grade($) { $rag_id2grade{$code2rag_id{$_[0]->value} || -1} || $rag_id2grade{-1}}
sub code2rag_id { $code2rag_id{$_[0]->value} || -2 }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Rag    => { layout_id => $col_id });
    $::db->delete(Ragval => { layout_id => $col_id });
}

###
### Instance
###

sub collect_form($$$)
{   my ($class, $old, $sheet, $params) = @_;
    my $changes = $class->SUPER::collect_form($old, $sheet, $params);
    my $extra = $changes->{extras};
    $extra->{no_alerts} = delete $extra->{no_alerts_rag};
    $extra->{code}      = delete $extra->{code_rag};
    $extra->{no_cache_update} = delete $extra->{no_cache_update_rag};
    $changes;
}

has _rag => (
    is      => 'rw',
    lazy    => 1,
    builder => sub { $::db->get_record(Rag => { layout_id => $_[0]->id }) },
);

sub code  { $_[0]->_rag->code } #XXX

sub _column_extra_update($)
{   my ($self, $update) = @_;
    my $code = delete $update->{code} || delete $update->{code_rag};
    defined $code or return;

    my %data = (code => $code);
    my $reload_id;
    if(my $old = $self->_rag)
    {   $::db->update(Rag => $old->id, \%data);
        $reload_id = $old->id;
    }
    else
    {   $data->{layout_id} = $self->id
        my $result = $::db->create(Rag => \%data);
        $reload_id = $result->id;
    }
    $self->_rag($::db->get_record(Rag => $reload_id));
}

1;
