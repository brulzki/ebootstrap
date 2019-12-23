#!/bin/bash
# Copyright 2019 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

source test-lib.sh

inherit ebootstrap

setup() {
    EROOT=$(mktemp -d /tmp/test-XXXXX)
    mkdir ${EROOT}/etc
    #XXX this should be handled by generate-make-conf
    mkdir -p ${EROOT}/etc/portage
}

teardown() {
    rm -rf ${EROOT}
    # clear env; these should be set within each test
    unset E_MAKE_CONF
}

tbegin "Test where no config is defined"

ebootstrap-configure-make-conf

is_debug && cat ${EROOT}/etc/portage/make.conf

assert "file exists" '
    [[ -f ${EROOT}/etc/portage/make.conf ]]
'
tend

#E_MAKE_CONF="
#       USE=bindist
#
#       PKGDIR=${E_PKGDIR:-/var/cache/packages}
#       DISTDIR=${E_DISTDIR:-/var/cache/distfiles}
#
#       FEATURES=getbinpkg
#       EMERGE_DEFAULT_OPTS=--usepkgonly --ignore-built-slot-operator-deps=y
#       PORTAGE_BINHOST=http://binpkg.example.com/packages/${PN}-${ARCH}
#"

#
#
tbegin "Test with config defined"

E_MAKE_CONF="
    HELLO=world
"
ebootstrap-configure-make-conf

is_debug && cat ${EROOT}/etc/portage/make.conf

assert "config is defined (with quotes added)" '
    grep -q "^HELLO=\"world\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test existing content is appended to"

E_MAKE_CONF="
    HELLO=world
"
echo "MARKER=1" > ${EROOT}/etc/portage/make.conf
ebootstrap-configure-make-conf

is_debug && cat ${EROOT}/etc/portage/make.conf

assert "initial content still exists" '
    grep -q "^MARKER=1$" ${EROOT}/etc/portage/make.conf
'
assert "config is appended" '
    grep -q "^HELLO=\"world\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test existing content is updated"

E_MAKE_CONF="
    HELLO=world
"
echo "HELLO=goodbye" > ${EROOT}/etc/portage/make.conf
ebootstrap-configure-make-conf

is_debug && cat ${EROOT}/etc/portage/make.conf

assert "initial content gone" '
    grep -q "^HELLO=goodbye$" ${EROOT}/etc/portage/make.conf
    [[ $? == 1 ]]
'
assert "config is appended" '
    grep -q "^HELLO=\"world\"$" ${EROOT}/etc/portage/make.conf
'
tend

#
tbegin "Test for idempotence"

E_MAKE_CONF="
    HELLO=world
"
ebootstrap-configure-make-conf
ebootstrap-configure-make-conf

is_debug && cat ${EROOT}/etc/portage/make.conf

assert "config is defined only once" '
    [[ $(grep "^HELLO=\"world\"" ${EROOT}/etc/portage/make.conf | wc -l) == 1 ]]
'
tend

