package Linkspace::User;

use warnings;
use strict;

use Log::Report 'linkspace';
use Scalar::Util     qw/blessed/;
use DateTime::Format::CLDR ();

use Linkspace::Util  qw/is_valid_email/;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

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

=item C<Linkspace::User::REST>, for automated coupling (TBI)
XXX or is this a simple Person?

=back

=head1 METHODS: Constructors
=cut

sub user_validate($)
{   my ($thing, $insert) = @_;

    ! defined $insert->{email} || is_valid_email $insert->{email}
        or error __"Invalid email address";

    ! $insert->{permissions} || $::session->user->is_admin
        or error __"You do not have permission to set the user's global permissions";
}

#------------------
=head1 METHODS: Permissions

=head2 is_admin
Returns true when the user has super user rights: can pass all checks.
=cut

# To be extended in sub-class
sub is_admin { 0 }

#-----------------
=head1 METHODS: Groups

=head2 my @groups = $user->groups;
=cut

#XXX Not sure whether this needs to be generic, but might simplify code.
sub groups { () }

=head2 my $has = $user->is_in_group($which);
=cut

sub is_in_group($) { 0 }

#-----------------
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
    build   => sub { $::linkspace->setting(users => 'cldr_pattern') || 'yyyy-MM-dd' },
);

=head2 my $can = $user->can_column($column, $action);
=cut

sub can_column($$)
{   my ($self, $column, $permission) = @_;
    1;
}

1;
