# Copyright (c) 2015-2017 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: ebootstrap
# @AUTHOR:
# Bruce Schultz <brulzki@gmail.com>
# @BLURB: A eclass for bootstrapping a system using portage.
# @DESCRIPTION:
# This eclass overrides the ebuild phases to bootstrap a gentoo
# installation.

# Environment variables used in processing the TARGET configuration:
#
# E_PROFILE   - used to set the symlink for /etc/portage/make.profile
#               eg E_PROFILE=gentoo:default/linux/x86/13.0
#
# E_PORTDIR   .
# E_DISTDIR   .
# E_PKGDIR    .
#             - these are used to configure /etc/portage/make.conf
#
# TIMEZONE    - used to set the /etc/timezone
#               eg TIMEZONE="Australia/Brisbane"
#
# LOCALE_GEN  - used to set /etc/locale.gen; a space separated list
#               of locales to append to the file
#               eg LOCALE_GEN="en_AU.UTF-8 en_AU.ISO-8859-1"
#               (note the use of the '.' in each locale)

if [[ ! ${_EBOOTSTRAP} ]]; then

# this results in very ungraceful errors, but prevents any major stuff-ups
if [[ "${EBUILD_PHASE}" != "info" ]]; then
	[[ ${EROOT} == "/" ]] && die "refusing to ebootstrap /"
fi

S=${EROOT}

EXPORT_FUNCTIONS pkg_info src_unpack src_prepare src_configure src_install pkg_preinst pkg_config eroot_mountpoints

#DEFAULT_REPO=${DEFAULT_REPO:-gentoo}
: ${DEFAULT_REPO:=gentoo}

# load the ebootstrap library functions
source ${EBOOTSTRAP_LIB}/ebootstrap-functions.sh

# STAGE3_ARCH
# this is used to identify the stage3 download
case "${ARCH}" in
	x86)
		STAGE3_ARCH="i686"
		;;
	*)
		STAGE3_ARCH="${ARCH}"
		;;
esac

ebootstrap_pkg_info() {
	ebootstrap-info
}

ebootstrap_src_unpack() {
	debug-print-function ${FUNCNAME} "${@}"

	# this is also checked in ebootstrap-unpack, but we want to be sure
	[[ ${EROOT} == "/" ]] && die "ERROR: refusing to install into /"

	ebootstrap-unpack
}

ebootstrap_src_prepare() {
	ebootstrap-prepare
}

ebootstrap_src_configure() {
	ebootstrap-configure
}

ebootstrap_src_install() {
	if [[ ${EBOOTSTRAP_BACKEND} == "ebuild" ]] && has nostage3 ${EBOOTSTRAP_FEATURES}; then
		# ebootstrap-install fails because of the environment which is
		# set up by portage; need to somehow reset the envionment and
		# run the install in a subshell
		einfo "ebootstrap_src_install"
		eerror "ebootstrap-install is not possible at this time"
	fi
	ebootstrap-install
}

ebootstrap_pkg_preinst() {
	die "ebootstrap ebuilds can not be merged into a system"
}

ebootstrap_pkg_config() {
	ebootstrap-configure-system
}

ebootstrap_eroot_mountpoints() {
	if [[ -f ${EROOT%/}/var/tmp/ebootstrap/mounts ]]; then
		egrep -v '^#|^/dev|^/proc' ${EROOT%/}/var/tmp/ebootstrap/mounts
	fi
}

# trace phase functions which have not been implemented
for _f in src_unpack  \
	  src_configure src_compile src_test src_install \
	  pkg_preinst pkg_postinst pkg_prerm pkg_postrm pkg_config; do
	# only override if the function is not already defined
	if ! type ebootstrap_${_f} >/dev/null 2>&1; then
		eval "ebootstrap_${_f}() {
			ewarn \"${_f}() is not implemented\"
		}"
		EXPORT_FUNCTIONS ${_f}
	fi
done
unset _f

_EBOOTSTRAP=1
fi
