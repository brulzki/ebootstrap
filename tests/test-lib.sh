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

# test stubs
ebootstrap-rc-update() { :; }

#
# test functions
#
test_count=0
test_failure=0
test_success=0
test_case=""

tbegin () {
    test_case="$@"
    printf "# %s\n" "${test_case}"
    __is_fn setup && setup
}

tend () {
    __is_fn teardown && teardown
    return 0
}

is_debug() {
    [[ $V == 1 ]]
}

test_ok_() {
    (( test_success++ ))
    printf "ok %s - %s\n" "${test_count}" "$1"
}

test_failure_() {
    (( test_failure++ ))
    printf "not ok %s - %s\n" "${test_count}" "$1"
    shift
    printf '%s\n' "$*" | sed -e 's/^/#	/'
}

assert() {
    local t="$1"; shift
    (( test_count++ ))
    eval "$@" </dev/null >&3 2>&4
    local ret=$?
    if [[ $ret == 0 ]]; then
        test_ok_ "$t"
    else
        test_failure_ "$t" "$@"
    fi
    return $ret
}

test_summary() {
    cat <<-EOF
	1..${test_count}
	# total   ${test_count}
	# success ${test_success}
	# failed  ${test_failure}
	EOF
}

trap 'test_summary' EXIT

if is_debug; then
    # set up verbose output redirection
    exec 3>&1 4>&2
else
    exec 3>/dev/null 4>/dev/null
fi
