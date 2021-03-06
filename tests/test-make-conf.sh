#!/bin/bash
# Copyright 2019 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# ebootstrap-configure-make-conf
#
# Generates the portage configuration in /etc/portage/make.conf. If
# the file already exists, the settings are updated as required,
# otherwise the file is created with the provided settings.
#
# Creates directories for PORTDIR, PKGDIR and DISTDIR.
#
# The config variables processed by this are:
#
# E_MAKE_CONF - sets config values in make.conf
#
# E_PORTDIR   - override the config values
# E_DISTDIR   .
# E_PKGDIR    .
#
# E_BINHOST   - sets PORTAGE_BINHOST and enables FEATURES=getbinpkg
#
# E_MAKE_CONF_CUSTOM
#             - customise the default make.conf file content

# TODO: confirm if we need to still create the directories from here
# (old function did this if E_*DIR variables exist)

source test-lib.sh

inherit ebootstrap

setup() {
    EROOT=$(mktemp -d /tmp/test-XXXXX)
    is_debug && echo "MAKE_CONF=${EROOT}/etc/portage/make.conf"
}

teardown() {
    is_debug && { cat ${EROOT}/etc/portage/make.conf; printf "========\n"; }
    rm -rf ${EROOT}
    # clear env; these should be set within each test
    unset E_MAKE_CONF E_PORTDIR E_PKGDIR E_DISTDIR E_MAKE_CONF_CUSTOM
}

#
tbegin "Test where no config is defined"

ebootstrap-configure-make-conf

assert "file exists" '
    [[ -f ${EROOT}/etc/portage/make.conf ]]
'
# check for the default expected variables
assert "check default PORTDIR" '
    grep -q "^PORTDIR=\"/var/db/repos/gentoo\"$" ${EROOT}/etc/portage/make.conf
'
assert "check default PKGDIR" '
    grep -q "^PKGDIR=\"/var/cache/binpkg\"$" ${EROOT}/etc/portage/make.conf
'
assert "check default DISTDIR" '
    grep -q "^DISTDIR=\"/var/cache/distfiles\"$" ${EROOT}/etc/portage/make.conf
'
# check that the directories have been created
assert "PORTDIR exists" '
    [[ -d ${EROOT}/var/db/repos/gentoo ]]
'
assert "PKGDIR exists" '
    [[ -d ${EROOT}/var/cache/binpkg ]]
'
assert "DISTDIR exists" '
    [[ -d ${EROOT}/var/cache/distfiles ]]
'
tend

#
tbegin "Test with custom config defined"

E_MAKE_CONF_CUSTOM="
    HELLO=world
"
ebootstrap-configure-make-conf

assert "config is defined (with quotes added)" '
    grep -q "^HELLO=\"world\"$" ${EROOT}/etc/portage/make.conf
'
# HELLO should be the only variable defined in make.conf
assert "the config from E_MAKE_CONF_CUSTOM is the default" '
    [[ $(grep "=" ${EROOT}/etc/portage/make.conf | wc -l) == 1 ]]
'
tend

#
tbegin "Test existing content is appended to"

E_MAKE_CONF_CUSTOM="
    HELLO=world
"
mkdir -p ${EROOT}/etc/portage
echo "MARKER=1" > ${EROOT}/etc/portage/make.conf
ebootstrap-configure-make-conf

assert "initial content still exists" '
    grep -q "^MARKER=1$" ${EROOT}/etc/portage/make.conf
'
assert "config is appended" '
    grep -q "^HELLO=\"world\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test existing content is updated"

E_MAKE_CONF_CUSTOM="
    HELLO=world
"
mkdir -p ${EROOT}/etc/portage
echo "HELLO=goodbye" > ${EROOT}/etc/portage/make.conf
ebootstrap-configure-make-conf

assert "initial content gone" '
    grep -q "^HELLO=goodbye$" ${EROOT}/etc/portage/make.conf
    [[ $? == 1 ]]
'
assert "new config is present" '
    grep -q "^HELLO=\"world\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test passing comments through"

E_MAKE_CONF_CUSTOM="
    # comment
    HELLO=world
    # goodbye
"
mkdir -p ${EROOT}/etc/portage
echo "HELLO=goodbye" > ${EROOT}/etc/portage/make.conf
ebootstrap-configure-make-conf

assert "comment remains" '
    grep -q "^# comment$" ${EROOT}/etc/portage/make.conf
'
assert "config is appended" '
    grep -q "^HELLO=\"world\"$" ${EROOT}/etc/portage/make.conf
'
assert "2nd comment remains" '
    grep -q "^# goodbye$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test for idempotence"

E_MAKE_CONF_CUSTOM="
    HELLO=world
"
ebootstrap-configure-make-conf
ebootstrap-configure-make-conf

assert "config is defined only once" '
    [[ $(grep "^HELLO=\"world\"" ${EROOT}/etc/portage/make.conf | wc -l) == 1 ]]
'
tend

#
tbegin "Test E_PORTDIR variable processing"

E_PORTDIR="e-portdir" ebootstrap-configure-make-conf

assert "check PORTDIR is set" '
    grep -q "^PORTDIR=\"e-portdir\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test E_PKGDIR variable processing"

E_PKGDIR="e-pkgdir" ebootstrap-configure-make-conf

assert "check PKGDIR is set" '
    grep -q "^PKGDIR=\"e-pkgdir\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test E_DISTDIR variable processing"

E_DISTDIR="e-distdir" ebootstrap-configure-make-conf

assert "check DISTDIR is set" '
    grep -q "^DISTDIR=\"e-distdir\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test with a realistic config"

# adapted from a sample eroot config
E_MAKE_CONF_CUSTOM="
       USE=bindist

       PKGDIR=/var/cache/binpkg
       DISTDIR=/var/cache/distfiles

       FEATURES=getbinpkg
       EMERGE_DEFAULT_OPTS=--usepkgonly --ignore-built-slot-operator-deps=y
       PORTAGE_BINHOST=http://binpkg.example.com/packages/${PN}-${ARCH}
"

ebootstrap-configure-make-conf

# check the predefined variables are still there
for v in USE PKGDIR DISTDIR FEATURES EMERGE_DEFAULT_OPTS PORTAGE_BINHOST; do
    assert "config contains ${v}" '
        grep -q "^${v}=" ${EROOT}/etc/portage/make.conf
    '
done
assert "correct number of setting in make.conf" '
    [[ $(grep "=" ${EROOT}/etc/portage/make.conf | wc -l) == 6 ]]
'
# Total number of lines (allows for added header)
assert "correct number of lines in make.conf" '
    [[ $(wc -l < ${EROOT}/etc/portage/make.conf) == 10 ]]
'
tend

#
tbegin "Test E_MAKE_CONF values are appended to default config"

E_MAKE_CONF="
    HELLO=world
"
ebootstrap-configure-make-conf

# check the default variables are still there
for v in PORTDIR PKGDIR DISTDIR; do
    assert "config contains ${v}" '
        grep -q "^${v}=" ${EROOT}/etc/portage/make.conf
    '
done
assert "new config is present" '
    grep -q "^HELLO=\"world\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test existing content is updated by E_MAKE_CONF"

E_MAKE_CONF="
    HELLO=world
"
mkdir -p ${EROOT}/etc/portage
echo "HELLO=goodbye" > ${EROOT}/etc/portage/make.conf
ebootstrap-configure-make-conf

assert "initial content gone" '
    grep -q "^HELLO=goodbye$" ${EROOT}/etc/portage/make.conf
    [[ $? == 1 ]]
'
assert "new config is present" '
    grep -q "^HELLO=\"world\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test E_MAKE_CONF updates defaults"

E_MAKE_CONF="
    PORTDIR=/usr/portage
"
ebootstrap-configure-make-conf

assert "check PORTDIR is updated" '
    grep -q "^PORTDIR=\"/usr/portage\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test E_*DIR precedence over E_MAKE_CONF"

E_MAKE_CONF="
    PORTDIR=/usr/portage
    PKGDIR=/usr/portage/packages
    DISTDIR=/usr/portage/distfiles
"
E_PORTDIR="/var/portdir"
E_PKGDIR="/var/pkgdir"
E_DISTDIR="/var/distdir"
ebootstrap-configure-make-conf

assert "check E_PORTDIR precedence" '
    grep -q "^PORTDIR=\"/var/portdir\"$" ${EROOT}/etc/portage/make.conf
'
assert "check E_PKGDIR precedence" '
    grep -q "^PKGDIR=\"/var/pkgdir\"$" ${EROOT}/etc/portage/make.conf
'
assert "check E_DISTDIR precedence" '
    grep -q "^DISTDIR=\"/var/distdir\"$" ${EROOT}/etc/portage/make.conf
'
assert "dirs are only defined once each" '
    [[ $(egrep "^(PORT|PKG|DIST)DIR=" ${EROOT}/etc/portage/make.conf | wc -l) == 3 ]]
'
tend

#
tbegin "Test E_*DIR precedence over E_MAKE_CONF - empty defaults"

E_MAKE_CONF_CUSTOM="
    PORTDIR=blah
"
E_MAKE_CONF="
    PORTDIR=/usr/portage
    PKGDIR=/usr/portage/packages
    DISTDIR=/usr/portage/distfiles
"
E_PORTDIR="/var/portdir"
E_PKGDIR="/var/pkgdir"
E_DISTDIR="/var/distdir"
ebootstrap-configure-make-conf

assert "check E_PORTDIR precedence" '
    grep -q "^PORTDIR=\"/var/portdir\"$" ${EROOT}/etc/portage/make.conf
'
assert "check E_PKGDIR precedence" '
    grep -q "^PKGDIR=\"/var/pkgdir\"$" ${EROOT}/etc/portage/make.conf
'
assert "check E_DISTDIR precedence" '
    grep -q "^DISTDIR=\"/var/distdir\"$" ${EROOT}/etc/portage/make.conf
'
assert "dirs are only defined once each" '
    [[ $(egrep "^(PORT|PKG|DIST)DIR=" ${EROOT}/etc/portage/make.conf | wc -l) == 3 ]]
'
tend

#
tbegin "Test value containing ="

E_MAKE_CONF_CUSTOM="
    EMERGE_DEFAULT_OPTS=--usepkgonly --ignore-built-slot-operator-deps=y
"
ebootstrap-configure-make-conf

assert "check E_DISTDIR precedence" '
    grep -q "^EMERGE_DEFAULT_OPTS=\"--usepkgonly --ignore-built-slot-operator-deps=y\"$" ${EROOT}/etc/portage/make.conf
'
# fails on the 2nd pass through
ebootstrap-configure-make-conf

assert "check E_DISTDIR precedence" '
    grep -q "^EMERGE_DEFAULT_OPTS=\"--usepkgonly --ignore-built-slot-operator-deps=y\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
# Tests for lines which append to a value (eg USE or FEATURES)
#

#
tbegin "Test appending values - append values to a line"
E_MAKE_CONF_CUSTOM="
    FEATURES=first
"
E_MAKE_CONF="
    FEATURES+=second
"
ebootstrap-configure-make-conf
assert "check the value is appended to an existing line" '
    grep -q "^FEATURES=\"first second\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test appending values - adding a line"
E_MAKE_CONF_CUSTOM="
"
E_MAKE_CONF="
    FEATURES+=second
"
ebootstrap-configure-make-conf
assert "check the value is added as a new line" '
    grep -q "^FEATURES=\"second\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test appending values - value exists already"
E_MAKE_CONF_CUSTOM="
    FEATURES=first second
"
E_MAKE_CONF="
    FEATURES+=second
"
ebootstrap-configure-make-conf
assert "check value is not added if it exists" '
    grep -q "^FEATURES=\"first second\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test appending values - value exists already (2)"
E_MAKE_CONF_CUSTOM="
    FEATURES=first second
"
E_MAKE_CONF="
    FEATURES+=first
"
ebootstrap-configure-make-conf
assert "check first value is not added if it exists" '
    grep -q "^FEATURES=\"first second\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test appending values - similar value exists "
E_MAKE_CONF_CUSTOM="
    FEATURES=firstline
"
E_MAKE_CONF="
    FEATURES+=first
"
ebootstrap-configure-make-conf
assert "check first value is added if it exists" '
    grep -q "^FEATURES=\"firstline first\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test appending values - adding multiple values (1)"
E_MAKE_CONF_CUSTOM="
    FEATURES=first
"
E_MAKE_CONF="
    FEATURES+=second
    FEATURES+=third
"
ebootstrap-configure-make-conf
assert "check all values added on a single line" '
    grep -q "^FEATURES=\"first second third\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test appending values - adding multiple values (2)"
E_MAKE_CONF_CUSTOM="
"
E_MAKE_CONF="
    FEATURES+=first
    FEATURES+=second
"
ebootstrap-configure-make-conf
assert "check all values added on a single line (2)" '
    grep -q "^FEATURES=\"first second\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
# PORTAGE_BINHOST
#

#
tbegin "Test setting PORTAGE_BINHOST from E_BINHOST"
E_MAKE_CONF_CUSTOM="
    FEATURES=first
"
E_BINHOST="http://binhost/"
ebootstrap-configure-make-conf
assert "check PORTAGE_BINHOST is set" '
    grep -q "^PORTAGE_BINHOST=\"http://binhost/\"$" ${EROOT}/etc/portage/make.conf
'
assert "check FEATURES=getbinpkg is enabled" '
    grep -q "^FEATURES=\"first getbinpkg\"$" ${EROOT}/etc/portage/make.conf
'
tend
