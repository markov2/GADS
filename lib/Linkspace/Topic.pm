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

package Linkspace::Topic;

use Log::Report 'linkspace';
use Linkspace::Util qw(make_wordlist);

use Moo;
extends 'Linkspace::DB::Table';

use namespace::clean;

sub db_table { 'Topic' }
sub db_also_bools { [ qw/click_to_edit/ ] }

### 2020-05-28: columns in GADS::Schema::Result::Topic
# id                    click_to_edit         prevent_edit_topic_id
# instance_id           description
# name                  initial_state

=head1 NAME

Linkspace::Topic - Topic of discussion

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS: constructors
=cut

has sheet => (
    is       => 'ro',
    required => 1,
    weakref  => 1,
);

#--------------
=head1 METHODS: Related topics
=cut

sub need_completed_topics
{   my $self = shift;
    (ref $self)->search_objects({prevent_edit_topic_id => $self->id}, sheet => $self->sheet);
}

sub show_need()
{   my ($self, $topics) = @_;
    make_wordlist(map $_->name, @$topics);
}

sub report_changes($)
{   my ($self, $update) = @_;
    my $name = $self->name;

    notice __x"Topic update: name from {old} to {new}",
        old => $name, new => $update->{name}
        if $self->name ne $update->{name};

    notice __x"Topic update: description from {old} to {new} for topic {name}",
        old => $self->description, new => $update->{description}, name => $name
        if  ($self->description || '') ne ($update->{description} || '');

    notice __x"Topic update: initial_state from {old} to {new} for topic {name}",
        old => $self->initial_state, new => $update->{initial_state}, name => $name
        if  ($self->initial_state || '') ne ($update->{initial_state} || '');

    notice __x"Topic update: click_to_edit from {old} to {new} for topic {name}",
        old => $self->click_to_edit, new => $update->{click_to_edit}, name => $name
        if  $self->click_to_edit != $update->{click_to_edit};

    my $new_edit_id = $update->{prevent_edit_topic_id};
    notice __x"Topic update: prevent_edit_topic_id from {old} to {new} for topic {name}",
        old => $self->prevent_edit_topic_id, new => $new_edit_id, name => $name
        if +($self->prevent_edit_topic_id //-1) != ($new_edit_id //-1);
}

1;
