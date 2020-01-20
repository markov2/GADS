package Linkspace::User;

use warnings;
use strict;

use Log::Report 'linkspace';

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

use Scalar::Util           qw(blessed);
use DateTime::Format::CLDR ();

=head1 NAME
Linkspace::User - person or process accessing information

=head1 SYNOPSIS

=head1 DESCRIPTION
All actions performed with data are on request by a person or process: the
data B<user>, so the main component for this generic component is granting
permissions.

The following specific user groups are planned:

=over 4

=item L<Linkspace::User::Person>, someone via the web interface

=item L<Linkspace::User::System>, a process

=item C<Linkspace::User::Test>, used for test scripts (TBI)

=item C<Linkspace::User::REST>, for automated coupling (TBI)

=cut

=head1 METHODS: Constructors

=cut

sub _user_value
{   my $user      = shift or return;
    my $firstname = $user->{firstname} || '';
    my $surname   = $user->{surname}   || '';
    "$surname, $firstname";
}

=head1 METHODS: Permissions

=head2 is_admin
Returns true when the user has super user rights: can pass all checks.
=cut

# To be extended in sub-class
sub is_admin { 0 }


=head1 METHODS: Groups

=head2 my @groups = $user->groups;
=cut

#XXX Not sure whether this needs to be generic, but might simplify code.
sub groups { () }

=head2 my $has = $user->has_group($group_id);
=cut

sub has_group($) { 1 }

=head1 METHODS: Other

=head2 my $dt = $user->local2dt($stamp, [$pattern]);
Convert the C<stamp>, which is in the user's locally prefered time format,
into a L<DateTime> object.
=cut

my %cldrs;   # cache them, probably expensive to generate

sub local2dt($)
{   my ($self, $stamp, $pattern) = @_;
    defined $stamp or return;
    return $stamp if blessed $stamp && $stamp->isa('DateTime');

    $pattern  ||= $self->date_pattern;
    $pattern   .= ' HH:mm:ss' if $stamp =~ / /;

    ($cldrs{$pattern} ||= DateTime::Format::CLDR->new(pattern => $pattern))
        ->parse_datetime($stamp);
}

=head2 my $string = $user->dt2local($dt, [$format, [%options]]);

Format some L<DateTime> object to the locale format (default the user's
prefered C<date_pattern>).  The boolean option C<include_time> will add
hours and minutes (not seconds) to the display.

=cut

sub dt2local($;$%)
{   my ($self, $dt, $pattern, %args) = @_;
    blessed $dt or return ();

    $pattern ||= $self->date_pattern;
    $pattern  .= 'HH:mm' if $args{include_time};

    ($cldrs{$pattern} ||= DateTime::Format::CLDR->new(pattern => $pattern))
        ->format_datetime($dt);
}

#XXX date_pattern should not be global for the instance, but at least
#XXX bound to a site, better per user a locale
has date_pattern => (
    is      => 'lazy',
    build   => sub {
       $::linkspace->settings_for('users')->{cldr_pattern} || 'yyyy-MM-dd';
    },
);

=head2 my $has = $user->has_draft($sheet);
=cut

sub has_draft
{   my ($self, $which) = @_;
    my $sheet_id = blessed $which ? $which->id : $which;
    $::db->search(Current => {
        instance_id  => $sheet_id,
        draftuser_id => $self->id,
        'curvals.id' => undef,
    }, {
        join => 'curvals',
    })->next;
}

sub export_hash
{   my $self = shift;
    #TODO Department, organisation etc not currently exported
    +{
        id                    => $self->id,
        firstname             => $self->firstname,
        surname               => $self->surname,
        value                 => $self->value,
        email                 => $self->email,
        username              => $self->username,
        freetext1             => $self->freetext1,
        freetext2             => $self->freetext2,
        password              => $self->password,
        pwchanged             => $self->pwchanged && $self->pwchanged->datetime,
        deleted               => $self->deleted   && $self->deleted->datetime,
        lastlogin             => $self->lastlogin && $self->lastlogin->datetime,
        account_request       => $self->account_request,
        account_request_notes => $self->account_request_notes,
        created               => $self->created   && $self->created->datetime,
        groups                => [ map $_->id, $self->groups ],
        permissions           => [ map $_->permission->name, $self->user_permissions ],
    };
}

sub retire
{   my ($self, %options) = @_;

    my $site   = $::session->site;

    if ($self->account_request)
    {   # Properly delete if account request - no record needed
        $self->delete;

        $::linkspace->mailer->send_user_rejected($user)
            if $options{send_reject_email};
        
        return;
    }

    $self->search_related(user_graphs => {})->delete;
    
    my $alerts = $self->search_related(alerts => {});
    my @alert_ids = map $_->id, $alerts->all;
    $::db->delete(AlertSend => { alert_id => \@alert_ids });
    $alerts->delete;

    $self->update({ lastview => undef });
    my $views    = $self->search_related(views => {});
    my @view_ids = map $_->id, $views->all;

    $::db->delete($_ => { view_id => \@view_ids })
        for qw/Filter ViewLayout Sort AlertCache Alert/;

    $views->delete;

    $self->update({ deleted => DateTime->now });

    $::linkspace->mailer->send_user_deleted($user);
}

1;
