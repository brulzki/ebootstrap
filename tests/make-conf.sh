
# ebootstrap-configure-make-conf
#
# Generates the portage configuration in /etc/portage/make.conf. If
# the file already exists, the settings are updated as required,
# otherwise the file is created with the provided settings.
#
# Creates directories for PORTDIR, PKGDIR and DISTDIR.
#
# The config variables processed by this are:
#
# E_MAKE_CONF - sets the default config file content/settings
#
# E_PORTDIR   - override the config values
# E_DISTDIR   .
# E_PKGDIR    .
ebootstrap-configure-make-conf() {
    local MAKE_CONF=${EROOT}/etc/portage/make.conf
    local config=()
    local vars=()
    local line
    local append=()
    local e_vars=()
    local v

    if [[ ! -v MAKE_CONF_DEFAULT ]]; then
        local MAKE_CONF_DEFAULT="
                  PORTDIR=\"/var/db/repos/gentoo\"
                  PKGDIR=\"/var/cache/binpkg\"
                  DISTDIR=\"/var/cache/distfiles\""
    fi

    if [[ ! -f ${MAKE_CONF} ]]; then
        mkdir -p ${MAKE_CONF%/*}
        printf "# Generated by ebootstrap\n" > ${MAKE_CONF}
        preprocess-make-conf-vars "${MAKE_CONF_DEFAULT}" >> ${MAKE_CONF}
    fi

    # read the existing variable names in the file
    while read line; do
        case "${line}" in
            *=*)
                vars+=( "${line%=*}" )
                ;;
        esac
    done < "${MAKE_CONF}"

    # pre-process the portage override vars
    for v in PORTDIR PKGDIR DISTDIR; do
        local n="E_${v}"
        [[ -v E_${v} ]] && e_vars+=( "${v}=${!n}" )
    done

    # generate and process sed edits to the default config
    {
        while read line; do
            case "${line}" in
                *=*)
                    if has "${line%=*}" "${vars[@]}"; then
                        printf "s/^${line%=*}=.*$/${line%=*}=\"${line#*=}\"/\n"
                    else
                        append+=( "${line%=*}=\"${line#*=}\"" )
                    fi
                    ;;
                *)
                    append+=( "${line}" )
                    ;;
            esac
        done <<< $(printf "%s\n" "${E_MAKE_CONF}" "${e_vars[@]}")

        if [[ ${#append[@]} > 0 ]]; then
            printf "$ {\n"
            printf "  a %s\n" "${append[@]}"
            printf "}\n"
        fi
    } | sed -i -f - ${MAKE_CONF}
}
