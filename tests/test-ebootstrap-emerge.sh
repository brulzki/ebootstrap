#!/bin/bash
# Copyright 2020 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# Test ebootstrap-emerge
#
# Runs emerge from the host to install into the target EROOT.

source test-lib.sh

# needed for access to get-profile
#inherit ebootstrap

setup() {
    EROOT=$(mktemp -d /tmp/test-XXXXX)
    mkdir -p ${EROOT}/etc/portage
    PROFILE_REPOS="gentoo"
    HOST_REPOS="[DEFAULT]
[gentoo]
location = /var/db/repos/gentoo"
}

teardown() {
    rm -rf ${EROOT}
    # clear env; these should be set within each test
    unset E_USERS HOST_REPOS PROFILE_REPOS
}

# stub the default pkg_config
ebootstrap_pkg_config() { :; }
debug-print-function() { :; }
emerge() { :; }


get-profile() { echo "${PROFILE_REPOS}"; }
# stub portageq to use the defined repos for the host; set HOST_REPOS
# in the test case to override the defaults
portageq() {
    case $1 in
        repos_config|get_repos|get_repo_path)
            if [[ $2 == "/" && -n "${HOST_REPOS}" ]]; then
                PORTAGE_REPOSITORIES="${HOST_REPOS}" /usr/bin/portageq "${@}"
            else
                /usr/bin/portageq "${@}"
            fi
            ;;
        *)
            /usr/bin/portageq "${@}"
            ;;
    esac
}

# __eroot-repos-config is used to generate a customised
# PORTAGE_REPOSITORIES value for ebootstrap-emerge. The expectation of
# emerge when run on the host with --root=EROOT is that the location is
# relative to the host root. Repository locations defined in the
# target eroot are modified to have EROOT is prepended to the path.
#
# (Note: ebootstrap expects that the eroot is a self-contained unit,
# so repos locations configured inside the eroot are relative to
# EROOT. This may be different from the expectation for other tools,
# such as catalyst and gentoo prefix.)
#
# Additionally, emerge needs access to the host profile, so if that is
# defined in an overlay which is not defined in the the eroot
# repos.conf, then the overlay repo is appended to the custom repos
# config.

#
tbegin "__eroot-repos-config : default repos"
assert "generate temporary PORTAGE_REPOSITORIES" '
    output=$(__eroot-repos-config ${EROOT} 2>&1)
'
echo "$output"
assert "output location is inside the eroot" '
    grep -q "^location = ${EROOT}/var/db/repos/gentoo$" <<< "${output}"
'
assert "no additional repos are added" '
    [[ $(grep "^location = " <<< "${output}" | wc -l) == 1 ]]
'
tend

#
tbegin "__eroot-repos-config : modified host repo"
HOST_REPOS="[DEFAULT]
[gentoo]
location = /usr/portage"
assert "generate temporary PORTAGE_REPOSITORIES" '
    output=$(__eroot-repos-config ${EROOT} 2>&1)
'
portageq get_repo_path / gentoo
portageq get_repo_path ${EROOT} gentoo
echo "$output"
assert "output location is inside the eroot" '
    grep -q "^location = ${EROOT}/var/db/repos/gentoo$" <<< "${output}"
'
assert "no additional repos are added" '
    [[ $(grep "^location = " <<< "${output}" | wc -l) == 1 ]]
'
tend

#
tbegin "__eroot-repos-config : modified eroot repo"
cat <<EOF > ${EROOT}/etc/portage/repos.conf
[DEFAULT]
[gentoo]
location = /usr/portage
EOF
assert "generate temporary PORTAGE_REPOSITORIES" '
    output=$(__eroot-repos-config ${EROOT} 2>&1)
'
portageq get_repo_path / gentoo
portageq get_repo_path ${EROOT} gentoo
echo "$output"
assert "output location is modified inside the eroot" '
    grep -q "^location = ${EROOT}/usr/portage$" <<< "${output}"
'
assert "no additional repos are added" '
    [[ $(grep "^location = " <<< "${output}" | wc -l) == 1 ]]
'
tend

#
tbegin "__eroot-repos-config : host profile defined in an overlay"
PROFILE_REPOS="overlay gentoo"
HOST_REPOS="[DEFAULT]
[gentoo]
location = /repos/gentoo
[overlay]
location = /var/db/repos/overlay"

assert "generate temporary PORTAGE_REPOSITORIES" '
    output=$(__eroot-repos-config ${EROOT} 2>&1)
'
echo "$output"
assert "output location is modified inside the eroot" '
    grep -q "^location = ${EROOT}/var/db/repos/gentoo$" <<< "${output}"
'
assert "output overlay location is modified inside the host root" '
    grep -q "^location = /var/db/repos/overlay$" <<< "${output}"
'
assert "no additional repos are added" '
    [[ $(grep "^location = " <<< "${output}" | wc -l) == 2 ]]
'
tend


#
tbegin "ebootstrap-emerge : --info"
# set up PKGDIR and DISTDIR values
cat <<EOF > ${EROOT}/etc/portage/make.conf
PKGDIR="/pkgdir"
DISTDIR="/distdir"
USE="blah"
EOF
assert "test ebootstrap-emerge" '
    output=$(ebootstrap-emerge --info 2>&1)
'
is_debug && echo "$output"
cat ${EROOT}/etc/portage/make.conf
assert "output PKGDIR is modified relative to EROOT" '
    grep -q "^PKGDIR=\"${EROOT}/pkgdir\"$" <<< "${output}"
'
assert "output DISTDIR is modified relative to EROOT" '
    grep -q "^DISTDIR=\"${EROOT}/distdir\"$" <<< "${output}"
'
tend
