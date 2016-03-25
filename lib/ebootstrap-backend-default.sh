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

    # this is probably dangerous
    #source ${PORTAGE_CONFIGROOT}/etc/portage/make.conf
    source ${config}
    export A=${SRC_URI##*/}
    export EROOT

    case $phase in
	info)
            echo config=${config}
            echo EROOT=${EROOT}
	    ;;
	fetch)
	    echo "Fetching"
	    ;;
	install)
	    echo "Unpacking ${DISTDIR}/${A}"
	    ebootstrap-unpack ${DISTDIR}/${A}
	    ;& # fall through to configure
	config)
	    echo "Configuring"
	    ebootstrap-configure
	    ;;
	clean)
	    echo "Cleaning"
	    ;;

    esac
}
