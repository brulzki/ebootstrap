#!/bin/bash
# Copyright 2020 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# ebootstrap-configure-package-files
#
# Generates the portage configuration in /etc/portage/package.*.
#
# The config variables processed by this are:
#
# E_PACKAGE_ACCEPT_KEYWORDS
# E_PACKAGE_USE
# E_PACKAGE_MASK
# E_PACKAGE_UNMASK
# E_PACKAGE_LICENSE

source test-lib.sh

inherit ebootstrap

setup() {
    EROOT=$(mktemp -d /tmp/test-XXXXX)
    mkdir -p ${EROOT}/etc/portage
}

teardown() {
    if is_debug; then
        ls -l ${EROOT}/etc/portage/package.*
        printf "========\n"
    fi
    rm -rf ${EROOT}
    # clear env; these should be set within each test
    unset E_PACKAGE_ACCEPT_KEYWORDS E_PACKAGE_USE
    unset E_PACKAGE_MASK E_PACKAGE_UNMASK E_PACKAGE_LICENSE
}

#
tbegin "package.accept_keywords"
assert "file is created" '
    E_PACKAGE_ACCEPT_KEYWORDS="sys-apps/ebootstrap ~amd64"
    ebootstrap-configure-package-files
    [[ -f ${EROOT}/etc/portage/package.accept_keywords ]]
'
assert "file is correct" '
    grep -q "^sys-apps/ebootstrap ~amd64$" ${EROOT}/etc/portage/package.accept_keywords
'
tend

#
tbegin "package.use"
assert "file is created" '
    E_PACKAGE_USE="sys-apps/ebootstrap -stuff"
    ebootstrap-configure-package-files
    [[ -f ${EROOT}/etc/portage/package.use ]]
'
assert "file is correct" '
    grep -q "^sys-apps/ebootstrap -stuff$" ${EROOT}/etc/portage/package.use
'
tend

#
tbegin "package.mask"
assert "file is created" '
    E_PACKAGE_MASK="sys-apps/ebootstrap"
    ebootstrap-configure-package-files
    [[ -f ${EROOT}/etc/portage/package.mask ]]
'
assert "file is correct" '
    grep -q "^sys-apps/ebootstrap$" ${EROOT}/etc/portage/package.mask
'
tend

#
tbegin "package.unmask"
assert "file is created" '
    E_PACKAGE_UNMASK="sys-apps/ebootstrap"
    ebootstrap-configure-package-files
    [[ -f ${EROOT}/etc/portage/package.unmask ]]
'
assert "file is correct" '
    grep -q "^sys-apps/ebootstrap$" ${EROOT}/etc/portage/package.unmask
'
tend

#
tbegin "package.license"
assert "file is created" '
    E_PACKAGE_LICENSE="sys-apps/ebootstrap gpl2"
    ebootstrap-configure-package-files
    [[ -f ${EROOT}/etc/portage/package.license ]]
'
assert "file is correct" '
    grep -q "^sys-apps/ebootstrap gpl2$" ${EROOT}/etc/portage/package.license
'
tend

#
tbegin "package.use in a directory"
mkdir -p ${EROOT}/etc/portage/package.use
assert "file is created in the directory" '
    E_PACKAGE_USE="sys-apps/ebootstrap -stuff"
    ebootstrap-configure-package-files &&
    [[ -f ${EROOT}/etc/portage/package.use/ebootstrap ]] &&
    grep -q "^sys-apps/ebootstrap -stuff$" ${EROOT}/etc/portage/package.use/ebootstrap
'
tend
