#!/bin/bash
# Copyright 2020 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

source ./test-lib.sh

setup() {
    EROOT=$(mktemp -d /tmp/test-XXXXX)
    is_debug && echo "EROOT=${EROOT}"
}

teardown() {
    rm -rf ${EROOT}
}

#
tbegin "Test trace.eroot"

output=$(../ebootstrap --prepare --nostage3 eroot/test-repos.eroot ${EROOT} 2>&1)
status=$?

assert "ebootstrap runs without errors" '
    [[ $status == 0 ]]
'
assert "repos config files are created" '
    [[ -f ${EROOT}/etc/portage/repos.conf/gentoo.conf ]] &&
    [[ -f ${EROOT}/etc/portage/repos.conf/overlay.conf ]] &&
    [[ -f ${EROOT}/etc/portage/repos.conf/dummy.conf ]]
'

tend
