#
# {{{ CDDL HEADER
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source. A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
# }}}
#
# Copyright 2018 OmniOS Community Edition (OmniOSce) Association.
#

log() {
    echo "$*"
}

HVM_Create_Diskvol() {
    typeset size=${1:-"8G"}
    typeset tag=${2:-$$}
    typeset root=${3:-"rpool/hvm-"}

    while zfs list $root$tag >/dev/null 2>&1; do
        tag+=0
    done

    zfs create -V $size $root$tag || exit 1
    lofi=`lofiadm -l -a /dev/zvol/rdsk/$root$tag` || exit 1
    echo "$root$tag:$lofi"
}

HVM_Destroy_Diskvol() {
    typeset lofi=$1

    lofiadm -d $lofi
}

HVM_Build_Devtree() {
    typeset root=$1
    typeset phys=$2
    typeset base=$3
    typeset -a abet=(`echo {a..z}`)
    typeset -i abetp

    ln -sf ../../devices/$phys:wd $root/dev/dsk/$base
    ln -sf ../../devices/$phys:wd,raw $root/dev/dsk/$base

    abetp=0  # slices start at a
    for p in `seq 0 15`; do
        val=${abet[$abetp]}
        ln -sf ../../devices/$phys:$val $root/dev/dsk/${base}s$p
        ln -sf ../../devices/$phys:$val,raw $root/dev/rdsk/${base}s$p
        ((abetp++))
    done

    abetp=16  # partitions start at q
    for p in `seq 0 4`; do
        val=${abet[$abetp]}
        ln -sf ../../devices/$phys:$val $root/dev/dsk/${base}p$p
        ln -sf ../../devices/$phys:$val,raw $root/dev/rdsk/${base}p$p
        ((abetp++))
    done

}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
