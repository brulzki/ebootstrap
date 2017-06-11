# Copyright (c) 2015-2017 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# Author: Bruce Schultz <brulzki@gmail.com>

# This is a backend which uses ebuild from portage to do the
# installation. The ebuild environment is overwritten from the typical
# portage configuration so that the customised configuration is used in
# place of the system configuration.

# override the portage settings
SYSTEM_REPOSITORIES="$(portageq repos_config /)"
export PORTAGE_CONFIGROOT=${EBOOTSTRAP_LIB}
export PORTDIR=${PORTAGE_CONFIGROOT}/overlay
export PORTAGE_REPOSITORIES="${SYSTEM_REPOSITORIES}"

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

copy-config-to-overlay() {
    local overlay="${1}" config="${2}"

    # create the overlay structure and copy the config file
    mkdir -p $overlay/{metadata,profiles,ebootstrap}
    echo "masters = gentoo" > ${overlay}/metadata/layout.conf
    echo ebootstrap > $overlay/profiles/categories
    echo ebootstrap > $overlay/profiles/arch.list
    local base=${config##*/}
    base=${base%.*}
    mkdir -p $overlay/ebootstrap/$base
    cp $config $overlay/ebootstrap/$base/$base-9999.ebuild

    # FIXME: why doesn't ebuild inherit from the ebootstrap overlay here?
    mkdir -p $overlay/eclass
    cp ${EBOOTSTRAP_LIB}/*.eclass $overlay/eclass

    # the new ebuild filename can be slurped out by the caller
    echo $overlay/ebootstrap/$base/$base-9999.ebuild
}

ebootstrap-backend() {
    local phase=$1 ebuild="${2}"
    export config="${ebuild}"

    if [[ "${ebuild##*.}" != "ebuild" ]]; then
        # ebuild expects the config to be an ebuild file in a proper overlay structure
        # so make a temporary copy if necessary
        local tmp_overlay=${PORTAGE_TMPDIR}/tmp-overlay
        ebuild=$(copy-config-to-overlay $tmp_overlay $ebuild)

        # add the overlay to repos.conf, otherwise ebuild tries
        # unsuccessfully to add it
        PORTAGE_REPOSITORIES="${SYSTEM_REPOSITORIES}
[tmp-overlay]
location = ${tmp_overlay}
"
    fi

    # set the ROOT so we can use EROOT in place of TARGET in the ebuilds but
    # this currently prints a warning about not finding the system profile
    # even though we override the profile in PORTAGE_CONFIGROOT ???
    export ROOT=${EROOT}

    export EBOOTSTRAP_LIB
    export EBOOTSTRAP_BARE
    export REPOPATH E_PKGDIR E_DISTDIR
    export LOCAL_REPOPATH LOCAL_PKGDIR LOCAL_DISTDIR

    /usr/bin/ebuild --skip-manifest "${ebuild}" ${phase}

    if [[ "${phase}" == "clean" ]]; then
        source ${EBOOTSTRAP_LIB}/ebootstrap-functions.sh
        ebootstrap-clean
        einfo Cleaning $tmp_overlay
        if [[ -d ${tmp-overlay} ]]; then
            rm -rf ${tmp-overlay}
        fi
    fi
}
