# Copyright (c) 2015 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: ebootstrap
# @AUTHOR:
# Bruce Schultz <brulzki@gmail.com>
# @BLURB: A eclass for bootstrapping a system using portage.
# @DESCRIPTION:
# This eclass overrides the ebuild phases to bootstrap a gentoo
# installation.

if [[ ! ${_EBOOTSTRAP} ]]; then

S=${TARGET}

EXPORT_FUNCTIONS pkg_info src_unpack pkg_preinst

unpack() {
  echo ${PWD}
  echo ">>> Unpack $@"
}

ebootstrap_src_unpack() {
	debug-print-function ${FUNCNAME} "${@}"

	[[ ! -d ${TARGET} ]] || die "TARGET rootfs directory already exists"
	mkdir -p ${TARGET}
	# don't use unpack; the handbook requires using the tar -p option
	echo ">>> Unpacking ${A} into ${TARGET}"
	tar -xopf ${DISTDIR}/${A} -C ${TARGET} || die "Failed extracting ${A}"

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

ebootstrap_pkg_info() {
	echo "TARGET=${TARGET}"
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