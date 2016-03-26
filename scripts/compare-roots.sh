#!/bin/bash

# compares 2 gentoo systems identify configuration differences
# the best indication of differences is found by comparing the between the packages and nonportage
if [[ $# -lt 2 ]]; then
    echo "usage: ${0%%/} root1 root2"
    exit -1
fi

declare -a eroots

while [[ ${#} > 0 ]]; do
    EROOT=${1}
    eroots+=(${EROOT##*/})
    echo "Scanning ${EROOT}"
    ls -d ${EROOT}/var/db/pkg/*/* | sed "s|^${EROOT}||g" > ${EROOT##*/}-packages.txt
    sudo ROOT=${EROOT} python2.7 /usr/bin/equery --no-color files "*" | sort -u > ${EROOT##*/}-portage.txt
    sudo find ${EROOT} \( -path \*/var/db/pkg -o -path \*/usr/share/mime \
         -o -path \*/var/cache/edb \) -prune -o -not -type l -print | sed "s|^${EROOT}||g" | \
        sort -u > ${EROOT##*/}-system.txt
    comm -13  ${EROOT##*/}-{portage,system}.txt >  ${EROOT##*/}-nonportage.txt
    shift
done

echo "
Compare results with the following commands:
diff -u {${eroots[0]},${eroots[1]}}-packages.txt | less
diff -u {${eroots[0]},${eroots[1]}}-nonportage.txt | less"

# immediate comparison
{
    diff -u {${eroots[0]},${eroots[1]}}-packages.txt
    diff -u {${eroots[0]},${eroots[1]}}-nonportage.txt
} | less
