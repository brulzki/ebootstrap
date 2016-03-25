# Copyright (c) 2015,2016 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# Author: Bruce Schultz <brulzki@gmail.com>

# This is a backend which uses ebuild from portage to do the
# installation. The ebuild environment is overwritten from the typical
# portage configuration so that the customised configuration is used in
# place of the system configuration.

# override the portage settings
export PORTAGE_CONFIGROOT=$(readlink -m ${0%/*})
export PORTDIR=${PORTAGE_CONFIGROOT}/tree
export PORTAGE_REPOSITORIES="[ebootstrap]
location = ${PORTDIR}
sync-type =
sync-uri =
"

if [[ ${UID} == 0 ]]; then
	: ${PORTAGE_TMPDIR:=/var/tmp/ebootstrap}
else
	# this enables running portage as non-root, but it spits out
	# lots of chgrp: operation not permitted errors which I can't
	# get rid of :(
	: ${PORTAGE_TMPDIR:=/var/tmp/ebootstrap-${UID}}
fi
export PORTAGE_TMPDIR
mkdir -p ${PORTAGE_TMPDIR} || die "Failed to create PORTAGE_TMPDIR"


ebootstrap-backend() {
    local phase=$1 ebuild="${2}"

    # set the ROOT so we can use EROOT in place of TARGET in the ebuilds but
    # this currently prints a warning about not finding the system profile
    # even though we override the profile in PORTAGE_CONFIGROOT ???
    export ROOT=${EROOT}

    export EBOOTSTRAP_LIB

    /usr/bin/ebuild "${ebuild}" ${phase}
}
