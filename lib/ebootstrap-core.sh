
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
    
    [[ -n "${config}" ]] && echo "${config}"
}
