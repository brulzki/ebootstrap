#!/bin/bash

source ../lib/ebootstrap-core.sh

: ${EBOOTSTRAP_LIB:=../lib}

# Let overlays override this so they can add their own testsuites.
TESTS_ECLASS_SEARCH_PATHS=( "${EBOOTSTRAP_LIB}" )

inherit() {
        local e path
        for e in "$@" ; do
                for path in "${TESTS_ECLASS_SEARCH_PATHS[@]}" ; do
                        local eclass=${path}/${e}.eclass
                        if [[ -e "${eclass}" ]] ; then
                                source "${eclass}"
                                continue 2
                        fi
                done
                die "could not find ${e}.eclass"
        done
}
EXPORT_FUNCTIONS() { :; }

tbegin () {
    echo "$@" >&2
    __is_fn setup && setup
}

tend () {
    __is_fn teardown && teardown
}

is_debug() {
    [[ $V == 1 ]]
}

assert() {
    local t="$1"; shift
    eval "$@"
    local ret=$?
    if [[ $ret == 0 ]]; then
        echo "PASSED: $t" >&2
    else
        echo "FAILED: $t" >&2
    fi
    return $ret
}

# stub
ebootstrap-rc-update() {
    :
}
