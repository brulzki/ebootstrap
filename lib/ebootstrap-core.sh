# Copyright (c) 2016-2018 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# @AUTHOR:
# Bruce Schultz <brulzki@gmail.com>
# @BLURB: Core functions for ebootstrap
# @DESCRIPTION:
# Implements core functions used by ebootstrap.

if [[ ! ${_EBOOTSTRAP_CORE} ]]; then

: ${EMERGE_OPTS:="--quiet"}

__is_fn() {
    #type -t "${1}" > /dev/null 2>&1
    declare -f "${1}" > /dev/null
}

__is_fn einfo || \
einfo() {
    # display a disposable message to the user
    echo "$@" >&2
}

__is_fn elog || \
elog() {
    # log a informative message for the user
    echo "$@" >&2
}

__is_fn ewarn || \
ewarn() {
    echo "$@" >&2
}

__is_fn eerror || \
eerror() {
    echo "$@" >&2
}

__is_fn die || \
die() {
    local code=$?
    [ ${#} -eq 0 ] || eerror "${*}"
    eerror "last exit return code was $code"
    exit 2
}

# has is copied from portage isolated-functions.sh
# License: GPLv2
__is_fn has || \
has() {
    local needle=$1
    shift

    local x
    for x in "$@"; do
        [ "${x}" = "${needle}" ] && return 0
    done
    return 1
}

__is_fn use || \
use() {
    local u=$1
    local found=0

    # if we got something like '!flag', then invert the return value
    if [[ ${u:0:1} == "!" ]] ; then
        u=${u:1}
        found=1
    fi

    has ${u} ${EBOOTSTRAP_USE}
    if has ${u} ${EBOOTSTRAP_USE} ; then
        ret=${found}
    else
        ret=$((!found))
    fi
    return ${ret}
}

# helper functions

load-global-config() {
    # the global config is loaded from
    #  - /etc/ebootstrap.conf

    if [[ -f "/etc/ebootstrap.conf" ]]; then
        source /etc/ebootstrap.conf
    fi

    # this should always be set... use default values otherwise
    : ${EBOOTSTRAP_CACHE:=/var/cache/ebootstrap}
    : ${REPOS_BASE:=/var/db/repos}
}

# __eroot-locations :: prints a list of paths to search for the eroot config
# The path is in the following order (portage repos are added only if an
# eroot dir exists within the repo):
#  - in $EBOOTSTRAP_OVERLAY
#  - in $PORTDIR_OVERLAY
#  - through the current configured host repos
#  - in $EBOOTSTRAP_LIB
__eroot-locations() {
    local repo repopath

    # EBOOTSTRAP_OVERLAY may be specified as a relative path, so we expand
    # that to the full path
    [[ -n ${EBOOTSTRAP_OVERLAY} ]] && realpath -sm ${EBOOTSTRAP_OVERLAY%/}/eroot

    # Add portage repos only if they have repos if an eroot dir exists
    [[ -n ${PORTDIR_OVERLAY} ]] && \
        -d [[ ${PORTDIR_OVERLAY}/eroot ]] && echo ${PORTDIR_OVERLAY%/}/eroot
    for repo in $(portageq get_repos /); do
        repopath=$(portageq get_repo_path / ${repo})
        [[ -d ${repopath}/eroot ]] && echo ${repopath}/eroot
    done
    echo ${EBOOTSTRAP_LIB}/eroot
}

find-config-file() {
    local name=${1}
    local config path potential_location

    case ${name} in
        /* | ./* | ../*)
            # looks like we were passed a file name
            debug-print "testing: ${name}"
            [[ -f ${name} ]] && config="$(readlink -m ${name})";
            ;;
        *)
            if [[ -f ${name} ]]; then
                config="$(readlink -m ${name})"
            else
                for path in "${EBOOTSTRAP_EROOT_LOCATIONS[@]}"; do
                    potential_location="${path}/${name%.eroot}.eroot"
                    debug-print "find-config-file: trying ${potential_location}"
                    if [[ -f ${potential_location} ]]; then
                        config="${potential_location}"
                        debug-print "found: ${config}"
                        break
                    fi
                done
            fi
            ;;
    esac

    [[ -n "${config}" ]] && echo "${config}" || false
}

__eroot-repos-config() {
    # prints a modified repositories configuration for the EROOT with locations
    # altered to be the full path relative to the host root
    portageq repos_config ${EROOT%/} | \
        awk -v EROOT="${EROOT%/}" -e '
            /^\[/ { print }
            /^location/ { print $1, $2, EROOT$3 }'

    # To run emerge with --config-root, all of the repos used by the host
    # profile must be defined in the target portage config, otherwise
    # portage can't find the host profile.

    # If the repo which contains the host's profile is not also included in
    # the eroot profiles, then the host profile cannot be found.

    # loop through the unique local repos referenced in the profile parents
    local profiles=( $(get-profile) )
    local eroot_repos="$(portageq get_repos ${EROOT%/})"
    for r in $(printf "%s\n" "${profiles[@]%%:*}" | sort -u); do
        if ! has ${r} ${eroot_repos}; then
            echo "[${r}]"
            echo "location = $(portageq get_repo_path / ${r})"
        fi
    done
}

ebootstrap-emerge() {
    # call the system emerge with options tailored to use within ebootstrap
    debug-print-function ${FUNCNAME} "${@}"

    # Make PKGDIR and DISTDIR within the EROOT relative to the host root
    # Override repository paths to be relative to the host root
    PKGDIR="${EROOT%/}/$(PORTAGE_CONFIGROOT="${EROOT%/}" portageq pkgdir 2> /dev/null)" \
    DISTDIR="${EROOT%/}/$(PORTAGE_CONFIGROOT="${EROOT%/}" portageq distdir 2> /dev/null)" \
    PORTAGE_REPOSITORIES="$(__eroot-repos-config)" \
    FEATURES="-news" /usr/bin/emerge --root=${EROOT%/} --config-root=${EROOT%/} ${EMERGE_OPTS} "$@"
}

_EBOOTSTRAP_CORE=1
fi
