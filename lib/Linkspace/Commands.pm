## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Commands;

use warnings;
use strict;

use File::Basename  qw(basename);
use Linkspace::Util qw(scan_for_plugins);

sub new(@) { my $class = shift; (bless {}, $class)->init( {@_} ) }

sub init($)
{   my ($self, $args) = @_;

    my $pkgs  = scan_for_plugins 'Command', load => $args->{load_all};
	my %names;
    foreach my $pkg (keys %$pkgs)
    {   my $name = $pkg =~ /.*\:\:(.*)/ ? $1 : $pkg;
        $names{lc $name} = $pkg;
    }
    $self->{LC_plugins} = \%names;

    $self;
}

=head2 my @names  = $cmds->plugin_names;
=cut

sub plugin_names() { keys shift->{LC_plugins} }

=head2 my $pkg = $cmds->get_plugin($name);
=cut

sub get_plugin($) {
    my ($self, $name) = @_;
    my $pkg = $self->{LC_plugins}{$name}
        or error __x"Command plugin {name} not found", name => $name;

    eval "use $pkg (); 1"
        or error __x"Command plugin {name} broken: failed loading {pkg}:\n{err}",
              name => $name, pkg => $pkg, err => $@;

    $pkg;
}

=head2 $pkg->global_help;
Print a generic help message to stdout.
=cut

sub global_help()
{   my $class = shift;
    my $self  = $class->new(load_all => 1);

    my $program = basename $0;
    warn "Usage: $program [--help|-?] COMMAND [SUBCMD OPTIONS]\n\ncommands:\n";

    print STDERR "   ", $self->get_plugin($_)->help_line, "\n"
        for sort $self->plugin_names;
}

=head2 $cmds->plugin_help($name);
Print a generic help message about the named plugin.
=cut

sub plugin_help($)
{   my ($self, $name) = @_;

    my $pkg = $self->get_plugin($name);

    print STDERR $pkg->plugin_help, "\n";
}

1;
