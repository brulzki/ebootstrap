# Copyright (c) 2015 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# @AUTHOR:
# Bruce Schultz <brulzki@gmail.com>
# @BLURB: Library functions for bootstrapping a gentoo root filesystem.
# @DESCRIPTION:
# Implements functions to asist with installation and initial
# configuration of a gentoo base system:
#  - ebootstrap-unpack()    : unpack a source archive
#  - ebootstrap-configure() : configure the system from the settings
#                             in the environment
#
# Environment variables used in processing the configuration:
#
# EROOT       - the path to the live target filesystem
#
# Portage configuration:
#
# REPOPATH    - the path where the overlay repositories are created
#               eg REPOPATH=/var/lib/portage/repos
#
# E_REPOS     - used to configure the files in /etc/portage/repos.conf/
#               this is a multiline variable of "name uri [options]"
#               eg E_REPOS="gentoo rsync://rsync.gentoo.org/gentoo-portage default
#                           overlay http://example.com/overlay.git auto-sync=no priority=0 sync-type="
#
# E_PROFILE   - used to set the symlink for /etc/portage/make.profile
#               eg E_PROFILE=gentoo:default/linux/x86/13.0
#
# E_MAKE_CONF - sets the default configuration for /etc/portage/make.conf
#
# E_PORTDIR   .
# E_DISTDIR   .
# E_PKGDIR    .
#             - override the config in /etc/portage/make.conf
#
# E_PACKAGE_USE
# E_PACKAGE_ACCEPT_KEYWORDS
# E_PACKAGE_MASK
# E_PACKAGE_LICENSE
#             - these are used to configure the corresponding
#               file in /etc/portage/package.*
#
# Sytem configuration:
#
# TIMEZONE    - used to set the /etc/timezone
#               eg TIMEZONE="Australia/Brisbane"
#
# LOCALE_GEN  - used to set /etc/locale.gen; a space separated list
#               of locales to append to the file
#               eg LOCALE_GEN="en_AU.UTF-8 en_AU.ISO-8859-1"
#               (note the use of the '.' in each locale)

if [[ ! ${_EBOOTSTRAP_FUNCTIONS} ]]; then

ebootstrap-unpack() {
	# unpack the source archive into ${EROOT}
	debug-print-function ${FUNCNAME} "${@}"

	local A="$1"

	[[ ${EROOT} == "/" ]] && dir "ERROR: refusing to install into \"/\""
	#[[ ! -d ${EROOT} ]] || die "rootfs directory already exists"
	mkdir -p ${EROOT}
	# test that the target directory is empty
	[[ "$(ls -A ${EROOT})" ]] && die "TARGET rootfs directory already exists"

	# don't use unpack; the handbook requires using the tar -p option
	echo ">>> Unpacking ${A} into ${EROOT}"
	tar -xopf ${A} -C ${EROOT} || die "Failed extracting ${A}"
}

unpack() {
	echo ${PWD}
	echo ">>> Unpack $@"
}

ebootstrap-unpack-alt() {
	# this has been adapted from vcs-snapshot.eclass
	debug-print-function ${FUNCNAME} "${@}"

	local A="$1"
	local f

	for f in ${A}
	do
		case "${f}" in
			*.tar|*.tar.gz|*.tar.bz2|*.tar.xz)
				local destdir=${EROOT}

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
				cd ${EROOT}
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
	local repo="$1" path

	# override the PORTAGE_CONFIGROOT to get the path relative to EROOT target
	# this doesn't work when run inside of portage
	path=$(env PORTAGE_CONFIGROOT=${EROOT} portageq get_repo_path / ${repo})

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
		${EROOT}/etc/portage/make.profile \
		|| die -q "Couldn't set new ${MAKE_PROFILE} symlink"

	return 0
}

get-repo-config() {
	local name=$1 uri=$2

	case "${uri}" in
		rsync://* | ssh://*)
			sync_type="rsync"
			;;
		git://* | git+ssh://* | http://*.git | https://*.git)
			sync_type="git"
			;;
		cvs://:*:* | :*:*)
			sync_type="cvs"
			;;
		*)
			sync_type=""
			;;
	esac

	for opt in ${*:3}; do
		case "${opt}" in
			default)
				echo "[DEFAULT]"
				echo "main-repo = ${name}"
				echo
				;;
			sync-type=*)
				sync_type="${opt#*=}"
				;;
			*)
				;;
		esac
	done

	echo "[${name}]"
	echo "location = ${REPOPATH}/${name}"
	echo "sync-uri = ${uri}"
	echo "sync-type = ${sync_type}"

	for opt in ${*:3}; do
		[[ "${opt}" =~ ^sync-type= ]] && continue
		[[ "${opt}" =~ .+=.* ]] && echo "${opt/=/ = }"
	done
}

set-repos-conf() {
	# repos is a multiline variable
	local repos="${1}"
	local repod="${EROOT}/etc/portage/repos.conf"

	[[ -f ${repod} ]] && mv ${repod} ${repod}-bak
	mkdir -p ${repod}

	echo "${repos}" | while read -a repo; do
		# skip blank lines and comments
		[[ -n "${repo}" ]] || continue
		[[ "${repo}" =~ ^# ]] && continue

		echo " - /etc/portage/repos.conf/${repo}.conf"
		get-repo-config "${repo[@]}" > ${repod}/${repo}.conf
	done
}

# This function takes multiline config inputs, generally from environment variables,
# and clean up the output to be suitable for the portage package.* config files.
preprocess-config-vars() {
	local add_blank=0

	# process each of the multiline args
	while [[ ${#} > 0 ]]; do

		echo "${1}" | while read line; do

			# strip trailing blank lines
			if [[ -z ${line} ]]; then
				(( add_blank++ ))
				continue
			fi
			for (( ; add_blank > 0 ; add_blank-- )); do
				echo
			done

			echo "${line}"
		done
		shift
		add_blank=0
	done
}

# This function takes multiline config inputs, generally from environment variables,
# and clean up the output to be suitable for the portage make.conf file.
preprocess-make-conf-vars() {
	# process each of the multiline args
	preprocess-config-vars "$@" | while read line; do

		# wrap the value in quotes
		if [[ ${line} =~ ([^=]*)=([^\"].*[^\"]) ]]; then
			line="${BASH_REMATCH[1]}=\"${BASH_REMATCH[2]}\""
		fi

		echo "${line}"
	done
}

ebootstrap-configure-repos() {
	if [[ -n "${E_REPOS}" ]]; then
		echo "Configuring /etc/portage/repos.conf"
		set-repos-conf "${E_REPOS}"
	fi
}

ebootstrap-configure-profile() {
	if [[ -n "${E_PROFILE}" ]]; then
		echo "Setting make.profile to ${E_PROFILE}"
		set_profile "${E_PROFILE}"
	fi
}

ebootstrap-configure-make-conf() {
	local MAKE_CONF=${EROOT}/etc/portage/make.conf

	local E_MAKE_CONF_HEADER="# Generated by ebootstrap"

	# This is generally added by portage; not necessary except for euses
	# Bug statuses Nov 2015:
	#   gentoo-bashcomp - bug #478444 (fixed in -20140911)
	#   euse - bug #474574 (confirmed, but fixed to use deprecated portageq envvar PORTDIR)
	#   euses and ufed - bug #478318 (confirmed, ufed fixed in 0.91; euses unknown)
	local E_MAKE_CONF_COMPAT="
		# Set PORTDIR for backward compatibility with various tools:
		#   gentoo-bashcomp - bug #478444
		#   euse - bug #474574
		#   euses and ufed - bug #478318
		#PORTDIR=\"${E_PORTDIR:-/usr/portage}\"
	"

	if [[ -n ${E_MAKE_CONF_HEADER} && ! -e ${MAKE_CONF} ]]; then
		preprocess-make-conf-vars "${E_MAKE_CONF_HEADER}" > ${MAKE_CONF}
	fi

	if [[ -n ${E_MAKE_CONF} ]]; then
		preprocess-make-conf-vars "${E_MAKE_CONF}" >> ${MAKE_CONF}
	fi
	#if [[ -n ${E_MAKE_CONF_EXTRA} ]]; then
	# 	preprocess-make-conf-vars "${E_MAKE_CONF_EXTRA}" >> ${MAKE_CONF}
	#fi

	if [[ -n ${E_MAKE_CONF_COMPAT} ]]; then
		preprocess-make-conf-vars "${E_MAKE_CONF_COMPAT}" >> ${MAKE_CONF}
	fi

	if [[ -n "${E_PORTDIR}" ]]; then
		echo "Setting make.conf PORTDIR to ${E_PORTDIR}"
		if grep -q "^PORTDIR=" ${MAKE_CONF}; then
			sed -i "s!^PORTDIR=.*!PORTDIR=\"${E_PORTDIR}\"!" ${MAKE_CONF}
		else
			echo "PORTDIR=${E_PORTDIR}" >> ${MAKE_CONF}
		fi
		mkdir -p ${EROOT}${E_PORTDIR}
	fi

	if [[ -n "${E_DISTDIR}" ]]; then
		echo "Setting make.conf DISTDIR to ${E_DISTDIR}"
		if grep -q "^DISTDIR=" ${MAKE_CONF}; then
			sed -i "s!^DISTDIR=.*!DISTDIR=\"${E_DISTDIR}\"!" ${MAKE_CONF}
		else
			echo "DISTDIR=${E_DISTDIR}" >> ${MAKE_CONF}
		fi
		mkdir -p ${EROOT}${E_DISTDIR}
	fi

	if [[ -n "${E_PKGDIR}" ]]; then
		echo "Setting make.conf PKGDIR to ${E_PKGDIR}"
		if grep -q "^PKGDIR=" ${MAKE_CONF}; then
			sed -i "s!^PKGDIR=.*!PKGDIR=\"${E_PKGDIR}\"!" ${MAKE_CONF}
		else
			echo "PKGDIR=${E_PKGDIR}" >> ${MAKE_CONF}
		fi
		mkdir -p ${EROOT}${E_PKGDIR}
	fi
}

ebootstrap-configure-package-files() {
	if [[ -n ${E_PACKAGE_ACCEPT_KEYWORDS} ]]; then
		preprocess-config-vars "${E_PACKAGE_ACCEPT_KEYWORDS}" > ${EROOT}/etc/portage/package.accept_keywords
	fi
	if [[ -n ${E_PACKAGE_USE} ]]; then
		preprocess-config-vars "${E_PACKAGE_USE}" > ${EROOT}/etc/portage/package.use
	fi
	if [[ -n ${E_PACKAGE_MASK} ]]; then
		preprocess-config-vars "${E_PACKAGE_MASK}" > ${EROOT}/etc/portage/package.mask
	fi
	if [[ -n ${E_PACKAGE_LICENSE} ]]; then
		preprocess-config-vars "${E_PACKAGE_LICENSE}" > ${EROOT}/etc/portage/package.license
	fi
}

ebootstrap-configure-portage() {
	# configure stuff in /etc/portage
	# - repos.conf
	# - make.profile
	# - make.conf
	# - package.*

	ebootstrap-configure-repos
	ebootstrap-configure-profile
	ebootstrap-configure-make-conf
	ebootstrap-configure-package-files
}

ebootstrap-configure-system() {
	# timezone
	if [[ -n "${TIMEZONE}" ]]; then
		echo "Setting timezone to ${TIMEZONE}"
		echo "${TIMEZONE}" > ${EROOT}/etc/timezone
		if [[ -e ${EROOT}/usr/share/zoneinfo/${TIMEZONE} ]]; then
			cp ${EROOT}/usr/share/zoneinfo/${TIMEZONE} ${EROOT}/etc/localtime
		fi
	fi

	# /etc/locale.gen
	if [[ -n "${LOCALE_GEN}" ]]; then
		echo "Configuring /etc/locale.gen"
		# strip any inital commented locales
		sed -i '/^#[a-z][a-z]_[A-Z][A-Z]/d' ${EROOT}/etc/locale.gen
		printf '%s\n' ${LOCALE_GEN} | sed 's/\./ /' >> ${EROOT}/etc/locale.gen
	fi
}

ebootstrap-configure() {
	ebootstrap-configure-portage
	ebootstrap-configure-system
}

_EBOOTSTRAP_FUNCTIONS=1
fi
