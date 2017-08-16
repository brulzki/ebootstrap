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
#
# E_HOSTNAME  - hostname of the target system
#
# E_PACKAGES  - array of package atoms which are to be installed
#
# E_SERVICES  - services to start in the default runlevel

if [[ ! ${_EBOOTSTRAP_FUNCTIONS} ]]; then

get-stage3-uri() {
    debug-print-function ${FUNCNAME} "${@}"

    local src="${1}" dest="${DISTDIR}/${1##*/}"
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
        #wget -N "${src}" -P "${DISTDIR}" >&2 && touch "${dest}"
        wget --no-use-server-timestamps "${src}" -O "${dest}" >&2
    fi
    local stage3_latest=$(tail -n1 "${dest}" | cut -d' ' -f1)

    echo "${src%/*}/${stage3_latest}"
}

ebootstrap-info() {
    einfo "config=${config}"
    einfo "DESCRIPTION=${DESCRIPTION}"
    einfo "EROOT=${EROOT}"
    einfo "ARCH=${ARCH}"
    einfo "SRC_URI=${SRC_URI}"
    einfo "P=${P}"
    einfo "PN=${PN}"
    einfo "A=${A}"
    einfo "S=${S}"
}

ebootstrap-fetch() {
    # fetch the source archive
    debug-print-function ${FUNCNAME} "${@}"

    # skip fetch step for bare install if no args were given
    [[ $# == 0 ]] && has bare ${EBOOTSTRAP_FEATURES} && return 0

    # if args were passed in, put them into local $SRC_URI
    [[ $# > 0 ]] && local SRC_URI=$(printf "%s\n" "$@")

    debug-print "SRC_URI=\"${SRC_URI}\""

    while read src; do
        # skip empty lines
        [[ -z ${src} ]] && continue
        [[ ${src##*/} == latest-stage3-*.txt ]] && src=$(get-stage3-uri "${src}")
        local dest="${src##*/}"
        debug-print "$src -> $dest"
        if has force ${EBOOTSTRAP_FEATURES} || [[ ! -f "${DISTDIR}/${dest}" ]]; then
            einfo "Fetching ${src}"
            wget "${src}" -O "${DISTDIR}/${dest}"
        fi
    done < <( echo "${SRC_URI}" )
}

var-expand() {
    eval echo ${!1}
}

fstype() {
    local path="${1}"

    df -T "${path}" | awk '/^\// { print $2 }' 2> /dev/null
}

create-root() {
    debug-print-function ${FUNCNAME} "${@}"

    local path=$(readlink -m "${1}")

    # ensure the parent directory is created first so that the btrfs test works
    mkdir -p "${path%/*}" || return -1

    if [[ $UID == 0 && $(fstype "${path%/*}") == "btrfs" ]]; then
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

    # skip unpack step for bare install if no args were given
    [[ $# == 0 ]] && has bare ${EBOOTSTRAP_FEATURES} && return 0

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
        tar -xpf "${DISTDIR}/${f}" -C "${EROOT}" || die "Failed extracting ${f}"
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

ebootstrap-prepare() {
    debug-print-function ${FUNCNAME} "${@}"
    local src dest lv

    if has bare ${EBOOTSTRAP_FEATURES} && [[ ! -d "${EROOT}/dev" ]]; then
        einfo ">>> Initialising bare rootfs in ${EROOT}"
        ebootstrap-init-rootfs
    fi

    if [[ $UID == 0 ]]; then
        # FIXME: this assumes that the paths are the same between the host
        # and the the rootfs... may not necessarily be the case
        einfo "Mounting portage dirs from host"
        for v in REPOPATH E_DISTDIR E_PKGDIR /dev /dev/pts /proc; do
            if [[ $v == /* ]]; then
                src="${v}"
                dest="${v}"
            else
                # $v is a variable name reference
                # expand $v to a LOCAL_ variable reference if necessary
                [[ -z ${!v} ]] && continue
                lv="LOCAL_${v/#E_/}"
                [[ -z ${!lv} ]] && lv="${v}"
                src="$(var-expand ${lv})"
                dest="$(var-expand ${v})"
            fi
            if grep -q " ${EROOT}${dest} " /proc/mounts; then
                # already mounted - assume its correct
                continue
            fi
            if [[ ! -d "${EROOT}${dest}" ]]; then
                einfo "Creating mount point at ${EROOT}${dest}"
                mkdir -p "${EROOT}${dest}"
            fi
            einfo "mounting from ${src} to ${EROOT}${dest}"
            mount --bind "${src}" "${EROOT}${dest}" || die "Failed to mount ${dest}"
        done
        cp /etc/resolv.conf "${EROOT}/etc/resolv.conf"
    else
        ewarn ">>> Skipping mounting of portage dirs without root access"
    fi

    # FIXME: these are my personal config preferences
    # needs to go into a hooks function somewhere
    mkdir -p ${EROOT}/mnt/{system,tmp}
    mkdir -p ${EROOT}/boot/efi
}

ebootstrap-chroot() {
    # TODO check the mounts are set up
    [[ -z "${EROOT}" ]] && return
    /usr/bin/chroot "${EROOT}" "$@"
}

ebootstrap-rc-update() {
    # (could link /etc/runlevels/default/ -> /etc/init.d/<service> ??)
    ebootstrap-chroot rc-update "$@"
}

install-packages() {
    einfo "Instaling packages: ${E_PACKAGES[@]}"
    if [[ ${#E_PACKAGES[@]} -gt 0 ]]; then
        #ebootstrap-emerge -au "${E_PACKAGES[@]}"
        # XXX: using ebootstrap-emerge here fails because the enewuser function
        # creates users in the host system only, not in the $EROOT system
        ebootstrap-chroot FEATURES="-news" emerge -u "${EMERGE_OPTS}" "${E_PACKAGES[@]}"
    fi
}

ebootstrap-install() {
    debug-print-function ${FUNCNAME} "${@}"

    if has bare ${EBOOTSTRAP_FEATURES}; then

        # install the system
        einfo "emerging system packages"
        # amd64 link from /lib->lib64 is created by baselayout
        # make sure this is done before merging other packages
        # (its probably bug is packages which install directly to /lib ?)
        ebootstrap-emerge -1 baselayout || die "Failed merging baselayout"
        ebootstrap-emerge -u1 @system || die "Failed merging @system"
        ebootstrap-emerge -u1 @world || die "Failed merging @world"
    fi

    # just automerge all the config changes
    ROOT=${EROOT} etc-update --automode -5

    # packages
    install-packages

    # default services
    for s in ${E_SERVICES}; do
        einfo "Adding ${s} to default runlevel"
        ebootstrap-rc-update add "${s}" default
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
    #        && die -q "No profile directory for target \"${target}\""

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
        if grep -q "^PORTDIR=" ${MAKE_CONF}; then
            sed -i "s!^PORTDIR=.*!PORTDIR=\"${E_PORTDIR}\"!" ${MAKE_CONF}
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

ebootstrap-configure-system() {
    # timezone
    if [[ -n "${TIMEZONE}" ]]; then
        einfo "Setting timezone to ${TIMEZONE}"
        echo "${TIMEZONE}" > ${EROOT}/etc/timezone
        if [[ -e ${EROOT}/usr/share/zoneinfo/${TIMEZONE} ]]; then
            cp ${EROOT}/usr/share/zoneinfo/${TIMEZONE} ${EROOT}/etc/localtime
        fi
    fi

    # /etc/locale.gen
    if [[ -n "${LOCALE_GEN}" ]]; then
        einfo "Configuring /etc/locale.gen"
        # strip any inital commented locales
        sed -i '/^#[a-z][a-z]_[A-Z][A-Z]/d' ${EROOT}/etc/locale.gen
        printf '%s\n' ${LOCALE_GEN} | sed 's/\./ /' >> ${EROOT}/etc/locale.gen
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
    if ! has bare ${EBOOTSTRAP_FEATURES}; then
        ebootstrap-configure-system
    fi
}

ebootstrap-config() {
    debug-print-function ${FUNCNAME} "${@}"

    ebootstrap-configure-system
}

ebootstrap-clean() {
    debug-print-function ${FUNCNAME} "${@}"

    has bare ${EBOOTSTRAP_FEATURES} || return 0

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
