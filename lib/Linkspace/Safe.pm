## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

#XXX Not used?  Was called of ::Code, but probably when the code was in Perl, not
#XXX in Lua.

package Linkspace::Safe;

use Safe;
use Moo;
with 'MooX::Singleton';

has _cpt => (
    is => 'lazy',
);

sub _build_cpt
{   my $self = shift;

    my $cpt = Safe->new;

    #Basic variable IO and traversal
    $cpt->permit_only(qw(null scalar const padany lineseq leaveeval rv2sv pushmark list return enter stub));
    
    #Comparators
    $cpt->permit(qw(not lt i_lt gt i_gt le i_le ge i_ge eq i_eq ne i_ne ncmp i_ncmp slt sgt sle sge seq sne scmp));

    # XXX fix later? See https://rt.cpan.org/Public/Bug/Display.html?id=89437
    $cpt->permit(qw(rv2gv));

    # Base math
    $cpt->permit(qw(preinc i_preinc predec i_predec postinc i_postinc postdec i_postdec int hex oct abs pow multiply i_multiply divide i_divide modulo i_modulo add i_add subtract i_subtract negate i_negate));

    #Conditionals
    $cpt->permit(qw(cond_expr flip flop andassign orassign and or xor));

    # String functions
    $cpt->permit(qw(concat substr index));

    # Regular expression pattern matching
    $cpt->permit(qw(match));

    #Advanced math
    #$cpt->permit(qw(atan2 sin cos exp log sqrt rand srand));

    $cpt;
}

sub eval
{   my ($self, $expr) = @_;
    my ($ret) = $self->_cpt->reval($expr);
    die $@ if @$;

    $ret;
}

1;

