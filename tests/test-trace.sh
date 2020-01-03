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

output=$(../ebootstrap eroot/trace.eroot ${EROOT} 2>&1)
status=$?

assert "ebootstrap runs without errors" '
    [[ $status == 0 ]]
'

tend
