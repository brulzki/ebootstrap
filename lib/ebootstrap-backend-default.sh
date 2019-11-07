# Copyright (c) 2015-2017 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# Author: Bruce Schultz <brulzki@gmail.com>

# This is the default backend which implements the install phases
# internally.

# inherit() and EXPORT_FUNCTIONS() adapted from portage ebuild.sh
# Copyright 1999-2015 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Sources all eclasses in parameters
declare -ix ECLASS_DEPTH=0
inherit() {
    ECLASS_DEPTH=$(($ECLASS_DEPTH + 1))
    if [[ ${ECLASS_DEPTH} > 1 ]]; then
        debug-print "*** Multiple Inheritence (Level: ${ECLASS_DEPTH})"
    fi

    local -x ECLASS
    local __export_funcs_var
    local location
    local potential_location

    # These variables must be restored before returning.
    local PECLASS=$ECLASS
    local prev_export_funcs_var=$__export_funcs_var

    while [ "$1" ]; do
        location=""
        potential_location=""

        ECLASS="$1"
        __export_funcs_var=__export_functions_$ECLASS_DEPTH
        unset $__export_funcs_var

        for repo_location in "${EBOOTSTRAP_ECLASS_LOCATIONS[@]}"; do
            potential_location="${repo_location}/${1}.eclass"
            #debug-print "inherit: trying ${potential_location}"
            if [[ -f ${potential_location} ]]; then
                location="${potential_location}"
                #debug-print "  eclass exists: ${location}"
                break
            fi
        done
        debug-print "inherit: $1 -> ${location}"
        [[ -z "${location}" ]] && die "ERROR: ${1}.eclass could not be found by inherit()"

        source "${location}" || die "died sourcing $location in inherit()"

        if [[ -z ${_IN_INSTALL_QA_CHECK} ]]; then
            # append vars to global variables
            [[ -n "${IUSE}" ]] && E_IUSE+="${E_IUSE:+ }${IUSE}"
            unset IUSE

            # define the exported functions
            if [[ -n ${!__export_funcs_var} ]] ; then
                for x in ${!__export_funcs_var} ; do
                    debug-print "EXPORT_FUNCTIONS: $x -> ${ECLASS}_$x"
                    declare -F "${ECLASS}_$x" >/dev/null || \
                        die "EXPORT_FUNCTIONS: ${ECLASS}_$x is not defined"
                    eval "$x() { ${ECLASS}_$x \"\$@\" ; }" > /dev/null
                done
            fi
            unset $__export_funcs_var
        fi
        shift
    done
    ((--ECLASS_DEPTH)) # Returns 1 when ECLASS_DEPTH reaches 0.
    if (( ECLASS_DEPTH > 0 )) ; then
        export ECLASS=$PECLASS
        __export_funcs_var=$prev_export_funcs_var
    else
        unset ECLASS __export_funcs_var
    fi
    return 0
}

# Exports stub functions that call the eclass's functions, thereby making them default.
# For example, if ECLASS="base" and you call "EXPORT_FUNCTIONS src_unpack", the following
# code will be eval'd:
# src_unpack() { base_src_unpack; }
EXPORT_FUNCTIONS() {
    if [ -z "$ECLASS" ]; then
        die "EXPORT_FUNCTIONS without a defined ECLASS"
    fi
    eval $__export_funcs_var+=\" $*\"
}

debug-print() {
    # adapted from portage ebuild.sh
    if [[ ${ECLASS_DEBUG_OUTPUT} == on ]]; then
        printf 'debug: %s\n' "${@}" >&2
    elif [[ -n ${ECLASS_DEBUG_OUTPUT} ]]; then
        printf 'debug: %s\n' "${@}" >> "${ECLASS_DEBUG_OUTPUT}"
    fi
}

debug-print-function() {
    # adapted from portage ebuild.sh
    debug-print "${1}: entering function, parameters ${*:2}"
}

ebootstrap-backend () {
    debug-print-function ${FUNCNAME} "${@}"

    local command="${1}" config="${2}" phases phase

    # internal portage-type variables... may be used in ebootstrap-functions
    P=${config##*/}
    PN=${P%.*}

    # the path to search for eclass files in iherit()
    EBOOTSTRAP_ECLASS_LOCATIONS=( ${EBOOTSTRAP_LIB}
                                  "${EBOOTSTRAP_EROOT_LOCATIONS[@]/%eroot/eclass}" )
    debug-print "EBOOTSTRAP_ECLASS_LOCATIONS=${EBOOTSTRAP_ECLASS_LOCATIONS[*]}"

    # load the config file
    source ${config}

    # add in dependency info from eclasses
    IUSE+="${IUSE:+ }${E_IUSE}"

    # export these for any portage utilities which may be called
    export DISTDIR
    export ROOT=${EROOT}

    # A is set based on the contents of SRC_URI
    local dest=()
    while read src; do
        dest+=(${src##*/})
    done < <( echo "${SRC_URI}" )
    A=$(IFS=' '; echo "${dest[*]}")
    unset dest

    # expand global vars
    for v in E_PKGDIR LOCAL_PKGDIR; do
        if [[ -n "${!v}" ]]; then
            declare ${v}="$(var-expand ${v})"
        fi
    done

    case $command in
        info)
            phases="info"
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
            phases="fetch unpack prepare configure install config"
            einfo "Installing to ${EROOT}"
            ;;
        config)
            einfo "Configuring"
            #phases="fetch unpack prepare configure install config"
            phases="config"
            ;;
        clean)
            phases="clean"
            ;;
        mountpoints)
            phases="mountpoints"
            ;;
        *)
            eerror "Invalid command: ${command}" && false
            ;;
    esac

    debug-print "phases=${phases}"
    for action in ${phases}; do
        debug-print ">>> executing phase: ${action}"
        case ${action} in
            info|config)
                # call the phase_func appropriate for the action
                pkg_${action}
                ;;
            fetch|clean)
                # do not need to track the state of these actions
                # there is no phase_func for these actions
                ebootstrap-${action}
                ;;
            mountpoints)
                eroot_${action}
                ;;
            *)
                # execute the current action if it has not already completed successfully
                if [[ ${action} != unpack && ! -d "${EROOT}" ]]; then
                    die "Invalid EROOT ${EROOT} (${action})"
                fi
                if [[ ${action} == prepare || ! -f "${EROOT}/var/tmp/ebootstrap/${action}" ]]; then
                    einfo ">>> ebootstrap phase: ${action}"
                    src_${action}
                    if [[ $? == 0 ]]; then
                        mkdir -p "${EROOT}/var/tmp/ebootstrap"
                        touch "${EROOT}/var/tmp/ebootstrap/${action}"
                    else
                        # don't process any further phases
                        debug-print "ERROR executing phase ${action}"
                        break
                    fi
                fi
                ;;
        esac
    done
}
