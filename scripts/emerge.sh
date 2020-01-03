#!/bin/bash

# This is a proof-of-concept script to demonstrate that the concept of
# overriding ebuild phases makes it possible to use portage to do atypical
# tasks.

# Usage:
# ./emerge [emerge opts]

__cfgr=$(readlink -m ${0%/*})

# override the portage settings
export PORTAGE_CONFIGROOT=${__cfgr}
export PORTDIR=${__cfgr}/tree
export PORTAGE_REPOSITORIES="[ebootstrap]
location = ${PORTDIR}
sync-type =
sync-uri ="

/usr/bin/emerge "$@"
