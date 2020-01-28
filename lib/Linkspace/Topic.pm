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

use Moo;
use namespace::clean;
extends 'GADS::Schema::Result::Topic';

=head1 NAME

Linkspace::Topic - Topic of discussion

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS: constructors
=cut

sub from_record($%)
{   my ($class, $record) = @_;
    bless $record, $class;
}

=head1 METHODS: Other
=cut

sub need_completed_topics_as_string
{   my $self = shift;
    my @topics = map $_->name, $self->need_completed_topics->all;

      ! @topics   ? ''
    : @topics==1  ? $topics[0]
    : do { 
        my $final = pop @topics;
        local $"  = ', ';
        "@topics and $final";
      };
}

sub need_completed_topics_count
{   my $self = shift;
    $self->need_completed_topics->count;
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
