## This file is part of Linkspace.  Copyright Ctrl O Ltd, UK.
## See https://www.ctrlo.com/linkspace.html
## Licensed under GPLv3 or newer, https://spdx.org/licenses/GPL-3.0-or-later

package Linkspace::Column::Code::Countries;
use base 'Exporter';

our @EXPORT_OK = 'is_country';

my @regexes;

sub is_country($)
{   my $country = shift;
    !! first { $country =~ $_ } @regexes;
}

# This list of regexes is copied directly from the plotly source code XXX when?
#XXX MO: why are some anchored with ^ or \b, but not all of them?
#XXX MO: it's a mess!

@regexes = map qr!$_!, qw/
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

1;
