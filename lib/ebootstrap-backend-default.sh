# Copyright (c) 2015,2016 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# Author: Bruce Schultz <brulzki@gmail.com>

# This is the default backend which implements the install phases
# internally.

source ${EBOOTSTRAP_LIB}/ebootstrap-functions.sh

inherit() {
    :
}

debug-print-function() {
    # adapted from portage ebuild.sh
    echo "${1}: entering function, parameters ${*:2}"
}

ebootstrap-backend () {
    local phase=$1 config="${2}"

    # load the config file
    source ${config}

    # export these for any portage utilities which may be called
    export DISTDIR
    export ROOT=${EROOT}

    # internal portage-type variables... may be used in ebootstrap-functions
    A=${SRC_URI##*/}

    case $phase in
	info)
            einfo config=${config}
            einfo EROOT=${EROOT}
	    ;;
	fetch)
	    einfo "Fetching"
	    ;;
        unpack)
            einfo "Unpacking ${DISTDIR}/${A}"
            ebootstrap-unpack ${DISTDIR}/${A}
            ;;
	install)
	    einfo "Unpacking ${DISTDIR}/${A}"
	    ebootstrap-unpack ${DISTDIR}/${A}
	    ;& # fall through to configure
	config)
	    einfo "Configuring"
	    ebootstrap-configure
	    ;;
	clean)
	    einfo "Cleaning"
	    ;;
        *)
            eerror "Invalid phase: ${phase}" && false
            ;;
    esac
}
