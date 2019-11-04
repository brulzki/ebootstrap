# Copyright (c) 2015-2017 Bruce Schultz <brulzki@gmail.com>
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
# REPOS_BASE  - the path where the overlay repositories are created
#               eg REPOS_BASE=/var/db/repos
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
# E_PACKAGE_UNMASK
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
#
# E_HOSTNAME  - hostname of the target system
#
# E_PACKAGES  - array of package atoms which are to be installed
#
# E_SERVICES  - services to start in the default runlevel

if [[ ! ${_EBOOTSTRAP_FUNCTIONS} ]]; then

get-stage3-uri() {
    debug-print-function ${FUNCNAME} "${@}"

    local src="${1}" dest="${EBOOTSTRAP_CACHE}/${1##*/}"
    local cache_age=0

    if [[ -f "${dest}" ]]; then
        cache_age=$(( ($(date +%s) - $(stat -c %Y "${dest}")) / 86400 ))
    fi

    # cache the latest-stage3 file for 14 days before trying to download again
    if [[ ! -f "${dest}" || ${cache_age} > 14 ]] || has force ${EBOOTSTRAP_FEATURES}; then
        ewarn "Fetching ${src}"
        # we use -N here to overwrite the existing file, but we touch
        # the file timestamp if the download was successful rather than
        # keeping the http file timestamp
        #wget -N "${src}" -P "${EBOOTSTRAP_CACHE}" >&2 && touch "${dest}"
        wget --no-use-server-timestamps "${src}" -O "${dest}" >&2
    fi
    local stage3_latest=$(tail -n1 "${dest}" | cut -d' ' -f1)

    echo "${src%/*}/${stage3_latest}"
}

ebootstrap-info() {
    einfo "config=\"${config}\""
    einfo "DESCRIPTION=\"${DESCRIPTION}\""
    einfo "EROOT=\"${EROOT}\""
    einfo "ARCH=\"${ARCH}\""
    einfo "SRC_URI=\"${SRC_URI}\""
    einfo "IUSE=\"${IUSE}\""
    einfo "P=\"${P}\""
    einfo "PN=\"${PN}\""
    einfo "A=\"${A}\""
    einfo "S=\"${S}\""
}

ebootstrap-fetch() {
    # fetch the source archive
    debug-print-function ${FUNCNAME} "${@}"

    # skip fetch step for nostage3 install if no args were given
    [[ $# == 0 ]] && has nostage3 ${EBOOTSTRAP_FEATURES} && return 0

    # if args were passed in, put them into local $SRC_URI
    [[ $# > 0 ]] && local SRC_URI=$(printf "%s\n" "$@")

    debug-print "SRC_URI=\"${SRC_URI}\""

    [[ -d "${EBOOTSTRAP_CACHE}" ]] || mkdir -p "${EBOOTSTRAP_CACHE}" || \
        die "ERROR: failed creating ${EBOOTSTRAP_CACHE}"

    while read src; do
        # skip empty lines
        [[ -z ${src} ]] && continue
        [[ ${src##*/} == latest-stage3-*.txt ]] && src=$(get-stage3-uri "${src}")
        local dest="${src##*/}"
        debug-print "$src -> $dest"
        if has force ${EBOOTSTRAP_FEATURES} || [[ ! -f "${EBOOTSTRAP_CACHE}/${dest}" ]]; then
            einfo "Fetching ${src}"
            wget "${src}" -O "${EBOOTSTRAP_CACHE}/${dest}"
        fi
    done < <( echo "${SRC_URI}" )
}

var-expand() {
    eval echo ${!1}
}

fstype() {
    local path="${1}"
    local t i=0 maxdepth=30
    local lastpath

    t=$(df -T "${path}" 2> /dev/null | awk '/^\// { print $2 }')

    while [[ ${t} == "" ]]; do
        (( i = i+1 ))
        # prevent infinite recursion
        [[ $i -ge $maxdepth ]] && break
        path="${path%/*}"
        [[ "${path}" == "${lastpath}" ]] && break
        lastpath="${path}"
        t=$(df -T "${path}" 2> /dev/null | awk '/^\// { print $2 }')
    done

    printf -- "${t}\n"
}

create-root() {
    debug-print-function ${FUNCNAME} "${@}"

    local path=$(readlink -m "${1}")

    # ensure the parent directory is created first so that the btrfs test works
    mkdir -p "${path%/*}" || return -1

    if [[ $UID == 0 ]] && command -v btrfs > /dev/null && \
           [[ $(fstype "${path%/*}") == "btrfs" ]]; then
        einfo "Creating btrfs subvolume ${path}"
        btrfs subvolume create "${path}"
    else
        mkdir -p "${path}"
    fi
}

ebootstrap-init-rootfs() {
    debug-print-function ${FUNCNAME} "${@}"

    # catalyst creates a bunch of .keep files around the place... I guess I should too
    local rootdirs="boot dev etc/profile.d etc/xml home media mnt opt proc root run
                    sys tmp usr/local/bin usr/local/sbin usr/src var/cache var/empty
                    var/lib var/log var/spool var/tmp"

    for d in $rootdirs; do
        mkdir -p "${EROOT}/${d}" && \
        touch "${EROOT}/${d}/.keep"
    done

    # set permissions of applicable directories
    # (normally done by the bootstrap ebuild with USE=build)
    chmod 700 "${EROOT}/root"
    chmod 1777 "${EROOT}/tmp" "${EROOT}/var/tmp"

    # create the minimal devices required to boot (with hotplugging)
    if [ $UID == 0 ]; then
        mknod "${EROOT}/dev/console" c 5 1
        mknod "${EROOT}/dev/null"    c 1 3
        mknod "${EROOT}/dev/ptmx"    c 4 2
        mknod "${EROOT}/dev/ram0"    b 1 0
        mknod "${EROOT}/dev/tty0"    c 5 0
        mknod "${EROOT}/dev/ttyS0"   c 4 64
    fi
}

ebootstrap-unpack() {
    # unpack the source archive into ${EROOT}
    debug-print-function ${FUNCNAME} "${@}"

    [[ ${EROOT} == "/" ]] && dir "ERROR: refusing to install into \"/\""

    if [[ ! -d ${EROOT} ]]; then
        create-root "${EROOT}" || die "Failed creating rootfs: ${EROOT}"
    fi

    # test that the target directory is empty
    [[ "$(ls -A "${EROOT}")" ]] && die "ERROR: rootfs directory already exists: ${EROOT}"

    # skip unpack step for nostage3 install if no args were given
    [[ $# == 0 ]] && has nostage3 ${EBOOTSTRAP_FEATURES} && return 0

    # if args were passed in, put them into local $SRC_URI
    [[ $# > 0 ]] && local A=$(printf "%s\n" "$@")

    debug-print "A=\"${A}\""

    for f in ${A}; do
        # skip empty lines
        [[ -z ${f} ]] && continue
        [[ ${f##*/} == latest-stage3-*.txt ]] && {
            f=$(get-stage3-uri "${f}")
            f=${f##*/}
        }
        # don't use portage unpack(); the handbook requires using the tar -p option
        einfo ">>> Unpacking ${f} into ${EROOT}"
        tar -xpf "${EBOOTSTRAP_CACHE}/${f}" -C "${EROOT}" || die "Failed extracting ${f}"
    done
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
                    -f "${EBOOTSTRAP_CACHE}/${f}" || die
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

ebootstrap-mount() {
    debug-print-function ${FUNCNAME} "${@}"
    local src=${1} dest=${2:-${1}}

    [[ -z ${src} ]] && return 1

    if grep -q " ${EROOT%/}${dest} " /proc/mounts; then
	# XXX already mounted - assume its correct
	return
    fi
    if [[ ! -d "${EROOT%/}${dest}" ]]; then
	einfo "Creating mount point at ${EROOT%/}${dest}"
	mkdir -p "${EROOT%/}${dest}"
    fi

    mkdir -p ${EROOT%/}/var/tmp/ebootstrap
    if [[ ! -f ${EROOT%/}/var/tmp/ebootstrap/mounts ]]; then
	printf "# EROOT=${EROOT}\n# src   dest\n" > ${EROOT%/}/var/tmp/ebootstrap/mounts
    fi
    einfo "mounting from ${src} to ${EROOT%/}${dest}"
    mount --bind "${src}" "${EROOT}${dest}" && \
        printf "${src} ${dest}\n" >> ${EROOT%/}/var/tmp/ebootstrap/mounts
}

# get-profile :: returns a space-separated list of parent profiles
get-profile() {
    debug-print-function ${FUNCNAME} "${@}"
    local root=${1:-/}
    local fix_links=0
    local -a p
    local x

    if [[ -L ${root%/}/etc/portage/make.profile ]]; then
        p=( $(readlink -n ${root%/}/etc/portage/make.profile) )
        fix_links=1
    elif [[ -f ${root%/}/etc/portage/make.profile/parent ]]; then
        while read x; do
            # skip blank lines and comments
            [[ -n "${x}" ]] || continue
            [[ "${x}" =~ ^# ]] && continue
            # append the profile
            p+=( "${x}" )
            [[ ${x} == ../../* ]] && fix_links=1
        done < ${root%/}/etc/portage/make.profile/parent
    else
        eerror "Missing profile in ${root}"
        return 1
    fi

    if [[ $fix_links == 1 ]]; then
        # convert repo path from relative link to repo:profile
        # adapted from do_show() in /usr/share/eselect/modules/profile.eselect
        # license: GPL2 or later

        local link repos repo_paths dir i

        # initialise the repos and repo_paths arrays
        if [[ -e ${root%/}/etc/portage/repos.conf || \
                  -f ${root%/}/etc/portage/make.conf ]]; then
             local DEFAULT_REPO=$(portageq repos_config ${root} | grep ^main-repo | cut -d ' ' -f 3)
            # sort: DEFAULT_REPO first, then alphabetical order
            repos=( $(portageq get_repos ${root} \
                          | sed "s/[[:space:]]\+/\n/g;s/^${DEFAULT_REPO}\$/ &/gm" \
                          | LC_ALL=C sort) )
            repo_paths=( $(portageq get_repo_path ${root} "${repos[@]}") ) \
                || die -q "get_repo_path failed"
            [[ ${#repos[@]} -eq 0 || ${#repos[@]} -ne ${#repo_paths[@]} ]] \
                && die -q "Cannot get list of repositories"
        else
            die "ERROR: get-profiles: /etc/portage has not been configured"
        fi

        for x in ${!p[@]}; do
            # check if the profile is already formed like repo:profile
            [[ ${p[${x}]} =~ ^.*:.* ]] && continue

            # a profile relative link always starts with ../..; strip that off so
            # that the link absolute from the rootfs
            link=${p[${x}]##../..}

            # Unfortunately, it's not obvious where to split a given path
            # in repository directory and profile. So loop over all
            # repositories and compare the canonicalised paths.
            for (( i = 0; i < ${#repos[@]}; i++ )); do
                dir="${repo_paths[i]}/profiles"
                if [[ ${link} == "${dir}"/* ]]; then
                    link=${link##"${dir}/"}
                    [[ ${repos[i]} != "${DEFAULT_REPO}" ]] \
                        && link=${repos[i]}:${link}
                    p[${x}]=${link}
                    break
                fi
            done
        done
    fi

    echo "${p[@]}"
}

ebootstrap-prepare() {
    debug-print-function ${FUNCNAME} "${@}"
    local src dest lv
    local repo host_path eroot_path

    if has nostage3 ${EBOOTSTRAP_FEATURES} && [[ ! -d "${EROOT}/dev" ]]; then
        einfo ">>> Initialising bare rootfs (nostage3) in ${EROOT}"
        ebootstrap-init-rootfs
    fi

    # ensure that the portage config is updated so it can be used for mounts
    ebootstrap-configure-portage

    cp /etc/resolv.conf "${EROOT}/etc/resolv.conf"

    if [[ $UID != 0 ]]; then
        ewarn ">>> Skipping mounting of portage dirs without root access"
        return
    fi

    # repos
    for repo in $(portageq get_repos ${EROOT%/}); do
        host_path=$(portageq get_repo_path / ${repo})
        target_path=$(portageq get_repo_path ${EROOT%/} ${repo})
        ebootstrap-mount ${host_path} ${target_path}
    done

    # distfiles
    local target_distdir=$(PORTAGE_CONFIGROOT=${EROOT%/} portageq distdir 2> /dev/null)
    ebootstrap-mount $(portageq distdir) ${target_distdir} || die

    # packages
    local host_pkgdir=$(portageq pkgdir)
    local target_pkgdir=$(PORTAGE_CONFIGROOT=${EROOT%/} portageq pkgdir 2> /dev/null)
    local target_profile="$(get-profile ${EROOT})"

    # Try to match the target pkgdir with a path from the host
    # XXX this won't work if we just use a simple name like packages
    if [[ "$(get-profile)" == "${target_profile}" \
              && ${target_pkgdir##*/} == ${host_pkgdir##*/} ]]; then
        # use the hosts pkgdir if the profiles match and the pkgdir names match
	ebootstrap-mount ${host_pkgdir} ${target_pkgdir} || die
    elif [[ -d ${host_pkgdir%/*}/${target_pkgdir##*/} ]]; then
	# found a relative packages dir with the correct name
	ebootstrap-mount ${host_pkgdir%/*}/${target_pkgdir##*/} ${target_pkgdir} || die
    else
	einfo "Creating PKGDIR=${target_pkgdir}"
	mkdir -p ${EROOT%/}/${target_pkgdir}
    fi

    # chroot mounts
    for v in /dev /dev/pts /proc; do
        ebootstrap-mount ${v} || die "Failed to mount ${v}"
    done
}

ebootstrap-chroot() {
    # TODO check the mounts are set up
    [[ -z "${EROOT}" ]] && return
    /usr/bin/chroot "${EROOT}" /usr/bin/env --unset=ROOT --unset=EROOT "$@"
}

ebootstrap-chroot-emerge() {
    ebootstrap-chroot /usr/bin/env FEATURES="-news" \
        /usr/bin/emerge ${EMERGE_OPTS} --root=/ "$@"
}

ebootstrap-rc-update() {
    # (could link /etc/runlevels/default/ -> /etc/init.d/<service> ??)
    ebootstrap-chroot rc-update "$@"
}

ebootstrap-install() {
    debug-print-function ${FUNCNAME} "${@}"

    if has nostage3 ${EBOOTSTRAP_FEATURES}; then

        # install the system
        einfo "emerging system packages"
        # amd64 link from /lib->lib64 is created by baselayout
        # make sure this is done before merging other packages
        # (its probably bug is packages which install directly to /lib ?)
        ebootstrap-emerge -1 baselayout || ewarn "Failed merging baselayout"
        ebootstrap-emerge -u1 @system || ewarn "Failed merging @system"
        #XXX Reinstall openssh through the chroot to fix useradd problem
        ebootstrap-chroot-emerge -1 net-misc/openssh || ewarn "Failed merging openssh"
    fi

    # ensure locales are updated
    ebootstrap-locale-gen --rebuild

    ebootstrap-chroot-emerge -u1 @world || die "Failed merging @world"

    # just automerge all the config changes
    ROOT=${EROOT} etc-update --automode -5

    # packages
    if [[ ${#E_PACKAGES[@]} -gt 0 ]]; then
        einfo "Instaling packages: ${E_PACKAGES[@]}"
        ebootstrap-chroot-emerge -u ${E_PACKAGES[@]} || ewarn "Failed merging packages"
    fi

    # default services
    for s in ${E_SERVICES}; do
        einfo "Adding ${s} to default runlevel"
        ebootstrap-rc-update add "${s}" default || ewarn "Failed rc-update ${s}"
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

# reimplement portageq get_repo_path
# the portageq version returns the path from the host system, not
# from within the root (Portage 2.3.40)
# Portage bug: https://bugs.gentoo.org/670082
portageq() {
    case ${1} in
        get_repo_path)
            [[ -z $3 ]] && { eerror "ERROR: insufficient parameters!"; return 3; }
            for repo in ${@:3}; do
                /usr/bin/portageq repos_config ${2}/ | \
                    awk -v REPO="[${repo}]" -e '
                        BEGIN { x=0 }
                        /^\[/ { if ($0==REPO) x=1; else x=0 }
                        /^location/ { if (x==1) print $3 }'
            done
            ;;
        get_repos)
            /usr/bin/portageq repos_config ${2}/ | \
                awk -e '
                    /^\[DEFAULT\]/ { next; }
                    /^\[/ { printf "%s ",substr($1,2,length($1)-2); }
                    END { printf "\n"; }'
            ;;
        *)
            /usr/bin/portageq "$@"
            ;;
    esac
}

# set_profile() is adapted from profile.eselect
# license: GPL2 or later
set_profile() {
    debug-print-function ${FUNCNAME} "${@}"
    local target=$1
    local repo repopath

    repo=${target%%:*}
    [[ ${repo} == "${target}" || -z ${repo} ]] && repo=${DEFAULT_REPO}
    target=${target#*:}
    repopath=$(portageq get_repo_path "${EROOT%/}/" "${repo}") || die -q "get_repo_path failed"

    [[ -z ${target} || -z ${repopath} ]] \
        && die -q "Target \"$1\" doesn't appear to be valid!"
    # don't assume that the path exists
    #[[ ! -d ${repopath}/profiles/${target} ]] \
    #        && die -q "No profile directory for target \"${target}\""

    # set relative symlink
    ln -snf "$(relative_name "${repopath}" /etc/portage)/profiles/${target}" \
       ${EROOT%/}/etc/portage/make.profile \
        || die -q "Couldn't set new ${MAKE_PROFILE} symlink"

    return 0
}

get-repo-config() {
    local name=$1 uri=$2
    local location="${REPOS_BASE}/${name}"
    local sync_type

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
            location=*)
                location="${opt#*=}"
                ;;
            sync-type=*)
                sync_type="${opt#*=}"
                ;;
            *)
                ;;
        esac
    done

    echo "[${name}]"
    echo "location = ${location}"
    echo "sync-uri = ${uri}"
    echo "sync-type = ${sync_type}"

    for opt in ${*:3}; do
        [[ "${opt}" =~ ^location= ]] && continue
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
        einfo "Configuring /etc/portage/repos.conf"
        set-repos-conf "${E_REPOS}"
    fi
}

ebootstrap-configure-profile() {
    if [[ -n "${E_PROFILE}" ]]; then
        einfo "Setting make.profile to ${E_PROFILE}"
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
    #         preprocess-make-conf-vars "${E_MAKE_CONF_EXTRA}" >> ${MAKE_CONF}
    #fi

    if [[ -n ${E_MAKE_CONF_COMPAT} ]]; then
        preprocess-make-conf-vars "${E_MAKE_CONF_COMPAT}" >> ${MAKE_CONF}
    fi

    if [[ -n "${E_PORTDIR}" ]]; then
        einfo "Setting make.conf PORTDIR to ${E_PORTDIR}"
        # use egrep & sed extended regexp (-E) here to match "#?"
        if egrep -q "^#?PORTDIR=" ${MAKE_CONF}; then
            sed -Ei "s!^#?PORTDIR=.*!PORTDIR=\"${E_PORTDIR}\"!" ${MAKE_CONF}
        else
            echo "PORTDIR=${E_PORTDIR}" >> ${MAKE_CONF}
        fi
        mkdir -p ${EROOT}${E_PORTDIR}
    fi

    if [[ -n "${E_DISTDIR}" ]]; then
        einfo "Setting make.conf DISTDIR to ${E_DISTDIR}"
        if grep -q "^DISTDIR=" ${MAKE_CONF}; then
            sed -i "s!^DISTDIR=.*!DISTDIR=\"${E_DISTDIR}\"!" ${MAKE_CONF}
        else
            echo "DISTDIR=${E_DISTDIR}" >> ${MAKE_CONF}
        fi
        mkdir -p ${EROOT}${E_DISTDIR}
    fi

    if [[ -n "${E_PKGDIR}" ]]; then
        einfo "Setting make.conf PKGDIR to ${E_PKGDIR}"
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
    if [[ -n ${E_PACKAGE_UNMASK} ]]; then
        preprocess-config-vars "${E_PACKAGE_UNMASK}" > ${EROOT}/etc/portage/package.unmask
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

set-hostname() {
    if [[ -n "${E_HOSTNAME}" ]]; then
        sed -e "s/hostname=\".*\"/hostname=\"${E_HOSTNAME}\"/" "${EROOT}/etc/conf.d/hostname" > "${EROOT}/etc/conf.d/._cfg0000_hostname"
    fi
}

ebootstrap-locale-gen() {
    local generate=0
    [[ "$1" == "--rebuild" ]] && generate=1
    if [[ -n "${LOCALE_GEN}" ]]; then
        einfo "Configuring /etc/locale.gen"
        # strip any inital commented locales
        sed -r '/^#?[a-z][a-z]_[A-Z][A-Z]/d' ${EROOT}/etc/locale.gen > ${EROOT}/etc/._cfg0000_locale.gen
        # Append the configured locales to locale.gen
        if [[ -f /usr/share/i18n/SUPPORTED ]]; then
            # Correct the name for the locale based on supported locale names
            for locale in ${LOCALE_GEN}; do
                grep "^${locale/\./.* }$" /usr/share/i18n/SUPPORTED
                [[ $? != 0 ]] && ewarn "Unsupported locale: $locale"
            done >> ${EROOT}/etc/._cfg0000_locale.gen
        else
            # This is a poor substitute when the SUPPORTED locale file is unavailable
            printf '%s\n' ${LOCALE_GEN} | sed 's/\./ /' >> ${EROOT}/etc/._cfg0000_locale.gen
        fi
        if ! diff -q ${EROOT}/etc/locale.gen ${EROOT}/etc/._cfg0000_locale.gen > /dev/null; then
            mv ${EROOT}/etc/._cfg0000_locale.gen ${EROOT}/etc/locale.gen
            generate=1
        fi
    fi
    if [[ $generate == 1 ]]; then
        einfo "Regenerating system locales"
        ebootstrap-chroot /usr/sbin/locale-gen || ewarn "Failed locale-gen"
    fi
}

ebootstrap-configure-system() {
    # /etc/locale.gen
    ebootstrap-locale-gen

    # timezone
    if [[ -n "${TIMEZONE}" ]]; then
        einfo "Setting timezone to ${TIMEZONE}"
        echo "${TIMEZONE}" > ${EROOT}/etc/timezone
        if [[ -e ${EROOT}/usr/share/zoneinfo/${TIMEZONE} ]]; then
            cp ${EROOT}/usr/share/zoneinfo/${TIMEZONE} ${EROOT}/etc/localtime
        fi
    fi

    # hostname
    if [[ -n "${E_HOSTNAME}" ]]; then
        einfo "Setting hostname to ${E_HOSTNAME}"
        sed -i "s/hostname=\".*\"/hostname=\"${E_HOSTNAME}\"/" "${EROOT}/etc/conf.d/hostname"
    fi
}

ebootstrap-configure() {
    debug-print-function ${FUNCNAME} "${@}"

    ebootstrap-configure-portage
    if ! has nostage3 ${EBOOTSTRAP_FEATURES}; then
        ebootstrap-configure-system
    fi
}

ebootstrap-config() {
    debug-print-function ${FUNCNAME} "${@}"

    ebootstrap-configure-system
}

ebootstrap-clean() {
    debug-print-function ${FUNCNAME} "${@}"

    # clean out any new items
    ROOT=${EROOT} eselect news read > /dev/null

    # cleanup the mounts
    # ensure we only unmount subdirs of EROOT (not EROOT itself)
    # sort -r ensures that lowest subdirs are umounted first
    for d in $(mount | grep ${EROOT}/ | cut -d ' ' -f 3 | sort -r); do
        umount ${d}
    done
}

_EBOOTSTRAP_FUNCTIONS=1
fi
