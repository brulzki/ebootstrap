# Copyright (c) 2015-2020 Bruce Schultz <brulzki@gmail.com>
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: trace
# @AUTHOR:
# Bruce Schultz <brulzki@gmail.com>
# @BLURB: A test eclass for tracing the progress of ebuild.
# @DESCRIPTION:
# This eclass overrides all ebuild function to simply print the function name.


if [[ ! ${_TRACE} ]]; then

for _f in pkg_pretend pkg_nofetch pkg_setup src_unpack src_prepare \
	  src_configure src_compile src_test src_install \
	  pkg_preinst pkg_postinst pkg_prerm pkg_postrm pkg_config; do
	eval "trace_${_f}() {
		ewarn \"${_f}()\"
		einfo \"PWD=\${PWD}\"
		einfo \"S=\${S}\"
		einfo \"A=\${A}\"
		einfo \"ROOT=\${ROOT}\"
		einfo \"EROOT=\${EROOT}\"
		[[ \${FUNCNAME} == trace_src_unpack ]] && mkdir -p \${S};
		return 0
	}"
	EXPORT_FUNCTIONS ${_f}
done
unset _f

_TRACE=1
fi
