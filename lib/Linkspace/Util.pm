=pod
GADS - Globally Accessible Data Store
Copyright (C) 2017 Ctrl O Ltd

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

use warnings;
use strict;

package Linkspace::Util;
use parent 'Exporter';

our @EXPORT_OK = qw/
    configure_util
    email_valid
    iso2datetime
    is_valid_id
    parse_duration
    scan_for_plugins
/;

use DateTime::Format::ISO8601   ();
use DateTime::Format::DateManip ();

use List::Util    qw(first);
use File::Glob    qw(bsd_glob);

=head1 NAME
Linkspace::Util - collection of useful functions

=head1 SYNOPSIS
  # You have to import all functions explicitly
  use Linkspace::Util qw(iso2datetime);

=head2 DESCRIPTION
Collections of functions used all over the place.  Sometimes it is hard
to decide whether some code should be in a function or as method to an
object.  Keep it simple!

=head2 FUNCTIONS
=cut

sub configure_util($)
{   my $config = shift;
}


=head2 email_valid $email or die;
Returns a true value when a C<user@domain.tld> string is passed: not a full
RFC2822 email address.
=cut

# Noddy email address validator. Not much point trying to be too clever here.
# We don't use Email::Valid, as that will check for RFC822 address as opposed
# to pure email address on its own.

sub email_valid($)
{   $_[0] =~ m/^[=+\'a-z0-9._-]+@[a-z0-9.-]+\.[a-z]{2,10}$/i;
}


=head2 my $dt = iso2datetime $string;
Convert a date represented as ISO8601 string to a L<DateTime> object.
=cut

sub iso2datetime($)
{   my $stamp = shift or return;
    DateTime::Format::ISO8601->parse_datetime($stamp);
}


=head2 my $is_valid = is_valid_id $string;
Returns the database 'id', which is always numeric and larger than zero.
Surrounding blanks are skipped.  For 
=cut

sub is_valid_id($)
{   defined $_[0] && $_[0] =~ /^\s*([0-9]+)\s*$/ && $1 != 0 ? $1 : undef;
}

=head2 my $duration = parse_duration $string;
Returns a L<DateTime::Duration> object.
=cut

sub parse_duration($) { DateTime::Format::DateManip->parse_duration($_[0]) }


=head2 my $plugins = scan_for_plugins $subpkg, %options;
Search the C<@INC> path (set by 'use lib' and the PERL5LIB environment
variable) for files which seem to contain plugins of a certain group.

It is a pity that there is no assurance that implementers are not
enforced to have matching package names and file names in Perl.  Gladly,
nearly everyone does it right automatically.

The scan will get all modules which match C<lib/Linkspace/$subpkg/*.pm>.

Example:

  my $pkgs_hash = scan_for_plugins 'Command', load => 1;
  # Will load  Linkspace::Commmand::Install  when it exists.

=cut

sub scan_for_plugins($%) {
    my ($subspace, %args) = @_;
    my $namespace = "Linkspace::$subspace";
    my $subpath   = $namespace =~ s!\:\:!/!gr;

   my $autoload   = $args{load};

    my %pkgs;
    foreach my $inc (@INC) {
        ref $inc && next;    # ignore code refs

        foreach my $filename (bsd_glob "$inc/$subpath/[!_]*.pm") {

            my $pkg = $filename =~ s!.*\Q$inc/!!r =~ s!\.pm$!!r =~ s!/!::!gr;
            next if $pkgs{$pkg};

            $pkgs{$pkg} = $filename;

            (my $plugin_base = $filename) =~ s!^\Q$inc/\E!!;
            my $has = first { /\Q$plugin_base\E$/ } keys %INC;
            next if $has;

            eval "use $pkg (); 1"
                or die "ERROR: failed to load plugin $pkg from $filename:\n$@";
        }
    }

    \%pkgs;
}

1;

