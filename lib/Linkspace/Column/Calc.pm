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
sub form_extras  { [ qw/code_calc no_alerts_calc return_type no_cache_update_calc/ ], [] }
sub has_filter_typeahead { $_[0]->return_type eq 'string' }
sub is_numeric() { my $rt = $_[0]->return_type; $rt eq 'integer' || $rt eq 'numeric' }
sub value_table  { 'Calcval' }

###
### Class
###

sub _remove_column($)
{   my $col_id = $_[1]->id;
    $::db->delete(Calc    => { layout_id => $col_id });
    $::db->delete(Calcval => { layout_id => $col_id });
}

sub _column_create($)
{   my ($class, $insert) = @_;
    my $column = $class->SUPER::_column_create($insert);
    $::db->create(Calc => { layout_id => $column->id, return_type => 'string' });
    $column;
}

###
### Instance
###

my %format2field = (
   date    => 'value_date',
   integer => 'value_int',
   numeric => 'value_numeric',
);

sub value_field()  { $format2field{$_[0]->return_type} || 'value_text' }
sub string_storage { $_[0]->value_field eq 'value_text' }

### The "Calc" table

sub calc           { ($_[0]->calcs)[0] )     #XXX why a has_many relationship?
sub code           { $_[0]->calc->{code} }
sub decimal_places { $_[0]->calc->{decimal_places} // 0 }
sub return_type    { $_[0]->calc->{return_type} }

sub _format_numeric($) { my $dc = $self->decimal_places

sub format_value($)
{   my ($self, $value) = @_;
    my $rt   = $column->return_type;

      $rt eq 'date'    ? $::session->site->dt2local($value)
    : $rt eq 'numeric' ? sprintf("%.*f", $self->decimal_places, $value)+0
    : $rt eq 'integer' ? int($value // 0) + 0   # remove trailing zeros
    : defined $value   ? "$value" : undef;

}

sub extra_update($)
{   my ($self, $extra) = @_;
    my $name      = $self->name;
    my $old       = $self->{calc};

    my %update    = %$old;
    $update{code} = my $code = delete $values->{code};
    notice __x"Update: code has been changed for field {name}", name => $name
        if $old->{code} ne $code;

    $update{return_type} = my $rt = delete $values->{return_type};
    notice __x"Update: return_type from {old} to {new} for field {name}",
        old => $self->return_type, new => $rt, name => $self->name
        if $old->{return_type} ne $rt;

    $update{decimal_places} = my $decimals = delete $values->{decimal_places};
    if($rt eq 'numeric')
    {   notice __x"Update: decimal_places from {old} to {new} for field {name}",
            old => $self->decimal_places, new => $decimals, name => $name
            if +($old->{decimal_places} // -1) != ($decimals // -1);
    }
    
    $::db->update(Calc => delete $update{id}, \%update);
};

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

sub resultset_for_values
{   my $self = shift;
    $self->value_field eq 'value_text' or return;
    $::db->(Calcval => { layout_id => $self->id }, { group_by  => 'me.value_text' });
}

sub _is_valid_value
{   my ($self, $value) = @_;
    my $rt = $self->return_type;
      $rt eq 'date'    ? ($self->parse_date($value) ? $value : undef)
    : $rt eq 'integer' ? ($value =~ /^\s*([-+]?[0-9]+)\s*$/ ? $1 : undef)
    : $rt eq 'numeric' ? (looks_like_number($value) ? $value : undef)
    :                    $value;
}

sub export_hash
{   my $self = shift;
    my $calc = $self->calc;
    $self->SUPER::export_hash(@_,
       code           => $calc->{code},
       return_type    => $calc->{return_type},
       decimal_places => $calc->{decimal_places},
    );
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
