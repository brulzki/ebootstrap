# Copyright (c) 2015 Bruce Schultz <brulzki@gmail.com>
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

EXPORT_FUNCTIONS pkg_info src_unpack src_configure pkg_preinst

#DEFAULT_REPO=${DEFAULT_REPO:-gentoo}
: ${DEFAULT_REPO:=gentoo}

unpack() {
  echo ${PWD}
  echo ">>> Unpack $@"
}

ebootstrap_src_unpack() {
	debug-print-function ${FUNCNAME} "${@}"

	[[ ${EROOT} == "/" ]] && die "ERROR: refusing to install into /"

	mkdir -p ${EROOT}
	# test that the target directory is empty
	[[ "$(ls -A ${EROOT})" ]] && die "TARGET rootfs directory already exists"

	# don't use unpack; the handbook requires using the tar -p option
	echo ">>> Unpacking ${A} into ${EROOT}"
	tar -xopf ${DISTDIR}/${A} -C ${EROOT} || die "Failed extracting ${A}"

	# unpack a portage snapshot
}

ebootstrap_src_unpack_alt() {
	# this has been adapted from vcs-snapshot.eclass
	debug-print-function ${FUNCNAME} "${@}"

	local f

	for f in ${A}
	do
		case "${f}" in
			*.tar|*.tar.gz|*.tar.bz2|*.tar.xz)
				local destdir=${TARGET}

				debug-print "${FUNCNAME}: unpacking ${f} to ${destdir}"

				# XXX: check whether the directory structure inside is
				# fine? i.e. if the tarball has actually a parent dir.
				mkdir -p "${destdir}" || die
				tar -C "${destdir}" -x --strip-components 1 \
					-f "${DISTDIR}/${f}" || die
				;;
			*)
				debug-print "${FUNCNAME}: falling back to unpack for ${f}"

				# fall back to the default method
				cd $TARGET
				unpack "${f}"
				;;
		esac
	done
}


# relative_name taken from /usr/share/eselect/libs/path-manipulation.bash
# license: GPL2 or later

# Wrapper function for either GNU "readlink -f" or "realpath".
canonicalise() {
	/usr/bin/readlink -f "$@"
}

# relative_name
# Convert filename $1 to be relative to directory $2.
# For both paths, all but the last component must exist.

relative_name() {
	# this function relies on extglob
	shopt -q extglob || local reset_extglob=1
	shopt -s extglob

	#local path=$(canonicalise "$1") dir=$(canonicalise "$2") c
	local path="$1" dir="$2" c

	while [[ -n ${dir} ]]; do
		c=${dir%%/*}
		dir=${dir##"${c}"*(/)}
		if [[ ${path%%/*} = "${c}" ]]; then
			path=${path##"${c}"*(/)}
		else
			path=..${path:+/}${path}
		fi
	done
	echo "${path:-.}"
	[[ ${reset_extglob} -eq 1 ]] && shopt -u extglob
}


get_repo_path() {
	local repo=$1 path

	# override the PORTAGE_CONFIGROOT to get the path relative to TARGET
	# this doesn't work when run inside of portage
	path=$(env PORTAGE_CONFIGROOT=${TARGET} portageq get_repo_path / ${repo})

	# fix the path in the case that nothing was found
	[[ -z "${path}" ]] && path="/usr/portage"

	echo "${path}"
}

# set_profile() is adapted from profile.eselect
# license: GPL2 or later
set_profile() {
	local target=$1
	local repo

	repo=${target%%:*}
	[[ ${repo} == "${target}" || -z ${repo} ]] && repo=${DEFAULT_REPO}
	target=${target#*:}
	repopath=$(get_repo_path "${repo}") || die -q "get_repo_path failed"

	[[ -z ${target} || -z ${repopath} ]] \
		&& die -q "Target \"$1\" doesn't appear to be valid!"
	# don't assume that the path exists
	#[[ ! -d ${repopath}/profiles/${target} ]] \
	#	&& die -q "No profile directory for target \"${target}\""

	# set relative symlink
	ln -snf "$(relative_name "${repopath}" /etc/portage)/profiles/${target}" \
		${TARGET}/etc/portage/make.profile \
		|| die -q "Couldn't set new ${MAKE_PROFILE} symlink"

	return 0
}

ebootstrap_src_configure() {
	# configure stuff in /etc/portage
	# - make.conf
	# - make.profile

	# make.profile
	if [[ -n "${E_PROFILE}" ]]; then
		echo "Setting make.profile to ${E_PROFILE}"
		set_profile "${E_PROFILE}"
	fi

	# make.conf
	if [[ -n "${E_PORTDIR}" ]]; then
		echo "Setting make.conf PORTDIR to ${E_PORTDIR}"
		if grep -q "^PORTDIR=" ${S}/etc/portage/make.conf; then
			sed -i "s!^PORTDIR=.*!PORTDIR=\"${E_PORTDIR}\"!" ${S}/etc/portage/make.conf
		else
			echo "PORTDIR=${E_PORTDIR}" >> ${S}/etc/portage/make.conf
		fi
		mkdir -p ${S}${E_PORTDIR}
	fi

	if [[ -n "${E_DISTDIR}" ]]; then
		echo "Setting make.conf DISTDIR to ${E_DISTDIR}"
		if grep -q "^DISTDIR=" ${S}/etc/portage/make.conf; then
			sed -i "s!^DISTDIR=.*!DISTDIR=\"${E_DISTDIR}\"!" ${S}/etc/portage/make.conf
		else
			echo "DISTDIR=${E_DISTDIR}" >> ${S}/etc/portage/make.conf
		fi
		mkdir -p ${S}${E_DISTDIR}
	fi

	if [[ -n "${E_PKGDIR}" ]]; then
		echo "Setting make.conf PKGDIR to ${E_PKGDIR}"
		if grep -q "^PKGDIR=" ${S}/etc/portage/make.conf; then
			sed -i "s!^PKGDIR=.*!PKGDIR=\"${E_PKGDIR}\"!" ${S}/etc/portage/make.conf
		else
			echo "PKGDIR=${E_PKGDIR}" >> ${S}/etc/portage/make.conf
		fi
		mkdir -p ${S}${E_PKGDIR}
	fi

	# timezone
	if [[ -n "${TIMEZONE}" ]]; then
		echo "Setting timezone to ${TIMEZONE}"
		echo "${TIMEZONE}" > ${S}/etc/timezone
		if [[ -e ${S}/usr/share/zoneinfo/${TIMEZONE} ]]; then
			cp ${S}/usr/share/zoneinfo/${TIMEZONE} ${S}/etc/localtime
		fi
	fi

	# /etc/locale.gen
	if [[ -n "${LOCALE_GEN}" ]]; then
		echo "Configuring /etc/locale.gen"
		# strip any inital commented locales
		sed -i '/^#[a-z][a-z]_[A-Z][A-Z]/d' ${S}/etc/locale.gen
		printf '%s\n' ${LOCALE_GEN} | sed 's/\./ /' >> ${S}/etc/locale.gen
	fi
}

ebootstrap_pkg_info() {
	echo EROOT=${EROOT}
	echo "WORKDIR=${WORKDIR}"
	echo "S=${S}"
	echo "ARCH=${ARCH}"
}

ebootstrap_pkg_preinst() {
	die "ebootstrap ebuilds can not be merged into a system"
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
