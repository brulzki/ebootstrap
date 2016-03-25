
#if [[ -f /lib/rc/sh/functions.sh ]]; then
#    source /lib/rc/sh/functions.sh
#fi

__is_fn() {
    #declare -f "${1}" > /dev/null
    type -f "${1}" > /dev/null 2>&1
}

__is_fn einfo || \
function einfo() {
    echo "$@"
}

__is_fn ewarn || \
function ewarn() {
    echo "$@"
}

__is_fn eerror || \
function eerror() {
    echo "$@"
}

__is_fn die || \
function die() {
    [ ${#} -eq 0 ] || eerror "${*}"
    exit 2
}

# helper functions

function load-global-config() {
    # the global config is loaded from
    #  - /etc/ebootstrap.conf
    #  - $XDG_CONFIG_HOME/ebootstrap/config

    # if script is run through sudo, the load the original users config
    # instead of the root user
    if [[ -n $SUDO_USER ]]; then
        local HOME=$(eval echo ~${SUDO_USER})
    fi

    local user_config=${XDG_CONFIG_HOME:-$HOME/.config}/ebootstrap/config

    if [[ -f "/etc/ebootstrap.conf" ]]; then
        source /etc/ebootstrap.conf
    fi
    if [[ -f ${user_config} ]]; then
        source ${user_config}
    fi
}

function find-config-file() {
    local name=${1} config

    case ${name} in
        /* | ./*)
            [[ -f ${name} ]] && config=${name};
            ;;
        *)
            if [[ -f ${name} ]]; then
                config=$(readlink -m ${1})
            elif [[ -f ${0%/*}/config/${1}.eroot ]]; then
                config=$(readlink -m ${0%/*}/config/${1}.eroot)
            else
                # equery means gentoolkit must be installed
                config=$(equery which ${1} 2>/dev/null)
            fi
            ;;
    esac
    
    [[ -n "${config}" ]] && echo "${config}" || false
}
