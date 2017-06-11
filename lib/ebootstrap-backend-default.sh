# Copyright (c) 2015-2017 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# Author: Bruce Schultz <brulzki@gmail.com>

# This is the default backend which implements the install phases
# internally.

source ${EBOOTSTRAP_LIB}/ebootstrap-functions.sh

inherit() {
    :
}

debug-print() {
    # adapted from portage ebuild.sh
    if [[ ${ECLASS_DEBUG_OUTPUT-on} == on ]]; then
        printf 'debug: %s\n' "${@}" >&2
    fi
}

debug-print-function() {
    # adapted from portage ebuild.sh
    debug-print "${1}: entering function, parameters ${*:2}"
}

ebootstrap-backend () {
    local command="${1}" config="${2}" phases phase

    # load the config file
    source ${config}

    # export these for any portage utilities which may be called
    export DISTDIR
    export ROOT=${EROOT}

    # internal portage-type variables... may be used in ebootstrap-functions
    local dest=()
    while read src; do
        dest+=(${src##*/})
    done < <( echo "${SRC_URI}" )
    A=$(IFS=' '; echo "${dest[*]}")
    unset dest
    P=${config##*/}
    PN=${P%.*}

    # expand global vars
    for v in E_PKGDIR LOCAL_PKGDIR; do
        if [[ -n "${!v}" ]]; then
            declare ${v}="$(var-expand ${v})"
        fi
    done

    case $command in
        info)
            ebootstrap-info
            ;;
        fetch)
            phases="fetch"
            ;;
        unpack)
            phases="fetch unpack"
            ;;
        prepare)
            einfo "Preparing ${EROOT}"
            phases="fetch unpack prepare"
            ;;
        configure)
            einfo "Configuring ${EROOT}"
            phases="fetch unpack prepare configure"
            ;;
        install)
            phases="fetch unpack prepare configure install"
            einfo "Installing to ${EROOT}"
            ;;
        config)
            einfo "Configuring"
            phases="fetch unpack prepare configure install config"
            ;;
        clean)
            phases="clean"
            ;;
        *)
            eerror "Invalid command: ${command}" && false
            ;;
    esac

    for action in ${phases}; do
        case ${action} in
            fetch|unpack|clean)
                # do not need to track the state of these actions
                ebootstrap-${action}
                ;;
            *)
                # execute the current action if it has not already completed successfully
                [[ -d "${EROOT}" ]] || die "Invalid EROOT ${EROOT} (${action})"
                mkdir -p "${EROOT}/var/tmp/ebootstrap"
                if [[ ! -f "${EROOT}/var/tmp/ebootstrap/${action}" ]]; then
                    einfo ">>> ebootstrap phase: ${action}"
                    ebootstrap-${action}
                    if [[ $? == 0 ]]; then
                        touch "${EROOT}/var/tmp/ebootstrap/${action}"
                    else
                        # don't process any further phases
                        break
                    fi
                fi
                ;;
        esac
    done
}
