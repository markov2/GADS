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

package Linkspace::Column::Calc;

use Moo;
use MooX::Types::MooseLike::Base qw/:all/;

extends 'Linkspace::Column::Code';

use Log::Report 'linkspace';
use Scalar::Util qw(looks_like_number);
use List::Util   qw(first);

###
### META
#
# There should have been many different Calc extensions, but these
# has been folded hacking the meta-data

__PACKAGE__->register_type;

sub can_multivalue { 1 }
sub has_filter_typeahead { $_[0]->return_type eq 'string' }
sub numeric() { my $rt = $_[0]->return_type; $rt eq 'integer' || $rt eq 'numeric' }
sub table          { 'Calcval' }

sub return_type()
{   my $thing = shift;
    ref $thing ? $thing->_rset_code->return_format : 'string';
)

my %format2field = (
   date    => 'value_date',
   integer => 'value_int',
   numeric => 'value_numeric',
);
sub value_field()  { $format2field{$_[0]->return_type} || 'value_text' }

#XXX
sub _build__rset_code
{   my $self = shift;
    $self->_rset or return;
    my ($code) = $sheet->layout->calcs;
    $code || $::db->resultset('Calc')->new({});
}

after build_values => sub {
    my ($self, $original) = @_;
    my $calc = $original->{calcs}->[0];
    $self->return_type($calc->{return_format});
    $self->decimal_places($calc->{decimal_places});
};

has decimal_places => (
    is      => 'rw',
    isa     => Maybe[Int],
);

###
### Class
###

sub remove($)
{   my $col_id = $_[1]->id;
    $::db->delete(Calc    => { layout_id => $col_id });
    $::db->delete(Calcval => { layout_id => $col_id });
}

###
### Instance
###

# Used to provide a blank template for row insertion
# (to blank existing values)
has '+blank_row' => (
    lazy => 1,
    builder => sub {
       +{
            value_date    => undef,
            value_int     => undef,
            value_numeric => undef,
            value_text    => undef,
        };
    },
);

has '+string_storage' => (
    default => sub { $_{0]->value_field eq 'value_text' },
);

# Returns whether an update is needed
sub write_code
{   my ($self, $layout_id, %options) = @_;
    my $rset = $self->_rset_code;
    my $need_update = !$rset->in_storage
        || $self->_rset_code->code ne $self->code
        || $self->_rset_code->return_format ne $self->return_type
        || $options{old_rset}->{multivalue} != $self->multivalue;
    $rset->layout_id($layout_id);
    $rset->code($self->code);
    $rset->return_format($self->return_type);
    $rset->decimal_places($self->decimal_places);
    $rset->insert_or_update;
    return $need_update;
}

sub resultset_for_values
{   my $self = shift;
    $self->value_field eq 'value_text' or return
    $::db->(Calcval => { layout_id => $self->id }, { group_by  => 'me.value_text' });
}

sub validate
{   my ($self, $value) = @_;
    my $rt = $self->return_type;
      $rt eq 'date'    ? $self->parse_date($value)
    : $rt eq 'integer' ? $value =~ /^-?[0-9]+$/
    : $rt eq 'numeric' ? looks_like_number($value)
    :                    1;
}

before import_hash => sub {
    my ($self, $values, %options) = @_;
    my $report = $options{report_only} && $self->id;
    notice __x"Update: code has been changed for field {name}", name => $self->name
        if $report && $self->code ne $values->{code};
    $self->code($values->{code});

    notice __x"Update: return_type from {old} to {new} for field {name}",
        old => $self->return_type, new => $values->{return_type}, name => $self->name
        if $report && $self->return_type ne $values->{return_type};
    $self->return_type($values->{return_type});

    notice __x"Update: decimal_places from {old} to {new} for field {name}",
        old => $self->decimal_places, new => $values->{decimal_places}, name => $self->name
        if $report && $self->return_type eq 'numeric' && (
            (defined $self->decimal_places xor defined $values->{decimal_places})
            || (defined $self->decimal_places && defined $values->{decimal_places} && $self->decimal_places != $values->{decimal_places})
        );
    $self->decimal_places($values->{decimal_places});
};

sub export_hash
{   my $self = shift;
    my $hash = $self->SUPER::export_hash;
    $hash->{code}           = $self->code;
    $hash->{return_type}    = $self->return_type;
    $hash->{decimal_places} = $self->decimal_places;
    $hash;
}

# This list of regexes is copied directly from the plotly source code
my @regexes = map qr!$_!, qw/
    afghan
    \\b\\wland
    albania
    algeria
    ^(?=.*americ).*samoa
    andorra
    angola
    anguill?a
    antarctica
    antigua
    argentin
    armenia
    ^(?!.*bonaire).*\\baruba
    australia
    ^(?!.*hungary).*austria|\\baustri.*\\bemp
    azerbaijan
    bahamas
    bahrain
    bangladesh|^(?=.*east).*paki?stan
    barbados
    belarus|byelo
    ^(?!.*luxem).*belgium
    belize|^(?=.*british).*honduras
    benin|dahome
    bermuda
    bhutan
    bolivia
    ^(?=.*bonaire).*eustatius|^(?=.*carib).*netherlands|\\bbes.?islands
    herzegovina|bosnia
    botswana|bechuana
    bouvet
    brazil
    british.?indian.?ocean
    brunei
    bulgaria
    burkina|\\bfaso|upper.?volta
    burundi
    verde
    cambodia|kampuchea|khmer
    cameroon
    canada
    cayman
    \\bcentral.african.republic
    \\bchad
    \\bchile
    ^(?!.*\\bmac)(?!.*\\bhong)(?!.*\\btai)(?!.*\\brep).*china|^(?=.*peo)(?=.*rep).*china
    christmas
    \\bcocos|keeling
    colombia
    comoro
    ^(?!.*\\bdem)(?!.*\\bd[\\.]?r)(?!.*kinshasa)(?!.*zaire)(?!.*belg)(?!.*l.opoldville)(?!.*free).*\\bcongo
    \\bcook
    costa.?rica
    ivoire|ivory
    croatia
    \\bcuba
    ^(?!.*bonaire).*\\bcura(c|ç)ao
    cyprus
    czechoslovakia
    ^(?=.*rep).*czech|czechia|bohemia
    \\bdem.*congo|congo.*\\bdem|congo.*\\bd[\\.]?r|\\bd[\\.]?r.*congo|belgian.?congo|congo.?free.?state|kinshasa|zaire|l.opoldville|drc|droc|rdc
    denmark
    djibouti
    dominica(?!n)
    dominican.rep
    ecuador
    egypt
    el.?salvador
    guine.*eq|eq.*guine|^(?=.*span).*guinea
    eritrea
    estonia
    ethiopia|abyssinia
    falkland|malvinas
    faroe|faeroe
    fiji
    finland
    ^(?!.*\\bdep)(?!.*martinique).*france|french.?republic|\\bgaul
    ^(?=.*french).*guiana
    french.?polynesia|tahiti
    french.?southern
    gabon
    gambia
    ^(?!.*south).*georgia
    german.?democratic.?republic|democratic.?republic.*germany|east.germany
    ^(?!.*east).*germany|^(?=.*\\bfed.*\\brep).*german
    ghana|gold.?coast
    gibraltar
    greece|hellenic|hellas
    greenland
    grenada
    guadeloupe
    \\bguam
    guatemala
    guernsey
    ^(?!.*eq)(?!.*span)(?!.*bissau)(?!.*portu)(?!.*new).*guinea
    bissau|^(?=.*portu).*guinea
    guyana|british.?guiana
    haiti
    heard.*mcdonald
    holy.?see|vatican|papal.?st
    ^(?!.*brit).*honduras
    hong.?kong
    ^(?!.*austr).*hungary
    iceland
    india(?!.*ocea)
    indonesia
    \\biran|persia
    \\biraq|mesopotamia
    (^ireland)|(^republic.*ireland)
    ^(?=.*isle).*\\bman
    israel
    italy
    jamaica
    japan
    jersey
    jordan
    kazak
    kenya|british.?east.?africa|east.?africa.?prot
    kiribati
    ^(?=.*democrat|people|north|d.*p.*.r).*\\bkorea|dprk|korea.*(d.*p.*r)
    kuwait
    kyrgyz|kirghiz
    \\blaos?\\b
    latvia
    lebanon
    lesotho|basuto
    liberia
    libya
    liechtenstein
    lithuania
    ^(?!.*belg).*luxem
    maca(o|u)
    madagascar|malagasy
    malawi|nyasa
    malaysia
    maldive
    \\bmali\\b
    \\bmalta
    marshall
    martinique
    mauritania
    mauritius
    \\bmayotte
    \\bmexic
    fed.*micronesia|micronesia.*fed
    monaco
    mongolia
    ^(?!.*serbia).*montenegro
    montserrat
    morocco|\\bmaroc
    mozambique
    myanmar|burma
    namibia
    nauru
    nepal
    ^(?!.*\\bant)(?!.*\\bcarib).*netherlands
    ^(?=.*\\bant).*(nether|dutch)
    new.?caledonia
    new.?zealand
    nicaragua
    \\bniger(?!ia)
    nigeria
    niue
    norfolk
    mariana
    norway
    \\boman|trucial
    ^(?!.*east).*paki?stan
    palau
    palestin|\\bgaza|west.?bank
    panama
    papua|new.?guinea
    paraguay
    peru
    philippines
    pitcairn
    poland
    portugal
    puerto.?rico
    qatar
    ^(?!.*d.*p.*r)(?!.*democrat)(?!.*people)(?!.*north).*\\bkorea(?!.*d.*p.*r)
    moldov|b(a|e)ssarabia
    r(e|é)union
    r(o|u|ou)mania
    \\brussia|soviet.?union|u\\.?s\\.?s\\.?r|socialist.?republics
    rwanda
    barth(e|é)lemy
    helena
    kitts|\\bnevis
    \\blucia
    ^(?=.*collectivity).*martin|^(?=.*france).*martin(?!ique)|^(?=.*french).*martin(?!ique)
    miquelon
    vincent
    ^(?!.*amer).*samoa
    san.?marino
    \\bs(a|ã)o.?tom(e|é)
    \\bsa\\w*.?arabia
    senegal
    ^(?!.*monte).*serbia
    seychell
    sierra
    singapore
    ^(?!.*martin)(?!.*saba).*maarten
    ^(?!.*cze).*slovak
    slovenia
    solomon
    somali
    south.africa|s\\\\..?africa
    south.?georgia|sandwich
    \\bs\\w*.?sudan
    spain
    sri.?lanka|ceylon
    ^(?!.*\\bs(?!u)).*sudan
    surinam|dutch.?guiana
    svalbard
    swaziland
    sweden
    switz|swiss
    syria
    taiwan|taipei|formosa|^(?!.*peo)(?=.*rep).*china
    tajik
    thailand|\\bsiam
    macedonia|fyrom
    ^(?=.*leste).*timor|^(?=.*east).*timor
    togo
    tokelau
    tonga
    trinidad|tobago
    tunisia
    turkey
    turkmen
    turks
    tuvalu
    uganda
    ukrain
    emirates|^u\\.?a\\.?e\\.?$|united.?arab.?em
    united.?kingdom|britain|^u\\.?k\\.?$
    tanzania
    united.?states\\b(?!.*islands)|\\bu\\.?s\\.?a\\.?\\b|^\\s*u\\.?s\\.?\\b(?!.*islands)
    minor.?outlying.?is
    uruguay
    uzbek
    vanuatu|new.?hebrides
    venezuela
    ^(?!.*republic).*viet.?nam|^(?=.*socialist).*viet.?nam
    ^(?=.*\\bu\\.?\\s?k).*virgin|^(?=.*brit).*virgin|^(?=.*kingdom).*virgin
    ^(?=.*\\bu\\.?\\s?s).*virgin|^(?=.*states).*virgin
    futuna|wallis
    western.sahara
    ^(?!.*arab)(?!.*north)(?!.*sana)(?!.*peo)(?!.*dem)(?!.*south)(?!.*aden)(?!.*\\bp\\.?d\\.?r).*yemen
    ^(?=.*peo).*yemen|^(?!.*rep)(?=.*dem).*yemen|^(?=.*south).*yemen|^(?=.*aden).*yemen|^(?=.*\\bp\\.?d\\.?r).*yemen
    yugoslavia
    zambia|northern.?rhodesia
    zanzibar
    zimbabwe|^(?!.*northern).*rhodesia'
/;

sub check_country
{   my $country = lc $_[1];
    !! first { $country =~ $_ } @regexes;
}

1;
