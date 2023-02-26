#!/bin/bash

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
# Copyright 2021 OmniOS Community Edition (OmniOSce) Association.
#

[ -n "$_KAYAK_LIB_HVM" ] && return
_KAYAK_LIB_HVM=1

. $SRCDIR/../lib/install_help.sh 2>/dev/null
. $SRCDIR/../lib/disk_help.sh
. $SRCDIR/../lib/net_help.sh

# Override the log function
function log {
    [ "$1" = "-o" ] && shift
    echo "$*"
}

function HVM_Create_Diskvol {
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

function HVM_Destroy_Diskvol {
    typeset lofi=$1

    lofiadm -d $lofi
}

function HVM_Build_Devtree {
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

function find_zfssend {
    typeset prefix=${1:-kayak}
    [ -z "$VERSION" ] && \
        VERSION="`nawk 'NR == 1 { sub(/^r/, "", $3); print $3 }' \
        /etc/release`"
    : ${ZFSSEND:=/kayak_image/${prefix}_r$VERSION.zfs.xz}
    [ -f "$ZFSSEND" ] || ZFSSEND="omnios-r$VERSION.zfs.xz"
    [ -f "$ZFSSEND" ] || ZFSSEND="omniosce-r$VERSION.zfs.xz"
}

function HVM_Image_Init {
    typeset size="${1:?size}"; shift
    typeset rpool="${1:?rpool}"; shift
    typeset tag="${1:?tag}"; shift
    typeset bename="${1:?bename}"; shift

    [ "$UID" != 0 ] && echo Need root privileges && exit 1

    HVMtag=$tag
    HVMrpool=$rpool
    HVMtmprpool=$tag$rpool
    HVMaltroot=/HVM${tag}root
    HVMpoolmount=/HVM$HVMtmprpool
    HVMbename=$bename

    HVMdev=`HVM_Create_Diskvol $size $tag` || exit 1
    HVMdataset="${HVMdev%:*}"
    HVMlofi="${HVMdev#*:}"
    HVMdisk="${HVMlofi/p0/}"
    HVMrlofi="${HVMlofi/dsk/rdsk}"
    HVMrdisk="${HVMdisk/dsk/rdsk}"

    SetupLog /tmp/kayak-$tag.log
}

function HVM_MBR_Init {
    echo "Setting up disk volume for MBR"

    # Create Solaris2 partition filling the entire disk
    fdisk -B $HVMrlofi
    fdisk -W - $HVMrlofi | tail -5 | head -2
    echo

    # Create slice 0 covering all of the non-reserved space
    OIFS="$IFS"; IFS=" ="
    set -- `prtvtoc -f $HVMrlofi`
    IFS="$OIFS"
    # FREE_START=2048 FREE_SIZE=196608 FREE_COUNT=1 FREE_PART=...
    start=$2; size=$4
    fmthard -d 0:2:01:$start:$size $HVMrlofi
    prtvtoc -s $HVMrlofi
    echo
}

function HVM_Image_Build {
    typeset poolopts="${1:?poolopts}"; shift
    typeset zfssend="${1:?zfssend}"; shift
    typeset hostname="${1:-omnios}"; shift
    typeset custom="$1"; shift
    typeset flags="$*"

    echo "Clearing any old pool"
    zpool destroy -f $HVMtmprpool 2>/dev/null || true

    zpool create $poolopts -R $HVMpoolmount -t $HVMtmprpool \
        $HVMrpool $HVMdisk

    BE_Create_Root $HVMtmprpool
    BE_Receive_Image cat "xz -dc" $HVMtmprpool $HVMbename $zfssend
    mkdir -p $HVMaltroot
    BE_Mount $HVMtmprpool $HVMbename $HVMaltroot raw
    BE_SetUUID $HVMtmprpool $HVMbename $HVMaltroot
    BE_LinkMsglog $HVMaltroot
    case $flags in
        *-noactivate*)  ;;
        *)              MakeBootable $HVMtmprpool $HVMbename ;;
    esac
    ApplyChanges
    SetTimezone UTC
    echo $hostname > $HVMaltroot/etc/nodename

    # Any additional customisation
    [ -n "$custom" ] && $custom "$HVMaltroot"

    # Force new IPS UUID on first pkg invocation.
    sed -i '/^last_uuid/d' $HVMaltroot/var/pkg/pkg5.image

    # Move disk links so they will be correctly generated on first boot.
    rm -f $HVMaltroot/dev/dsk/* $HVMaltroot/dev/rdsk/*

    # Reconfigure on first boot
    touch $HVMaltroot/reconfigure

    #
    # First boot configuration
    #

    # Pools are sometimes created with no features enabled and then
    # updated on first boot to add all features supported on the target
    # system.
    Postboot 'zpool upgrade -a'
    # Give the pool a unique GUID
    Postboot "zpool reguid $HVMrpool"
}

function HVM_Image_Finalise {
    typeset slice="$1"; shift
    typeset blk="$1"; shift
    typeset phys="$1"; shift
    typeset devid="$1"; shift
    typeset flags="$*"

    Postboot 'exit $SMF_EXIT_OK'

    echo "Unmount"
    BE_Umount $HVMbename $HVMaltroot raw
    rmdir $HVMaltroot

    echo "Export"
    zpool export $HVMtmprpool

    $SRCDIR/../bin/zpool_patch -v ${HVMdisk}s$slice "$blk" "$phys" "$devid"

    case $flags in
        *-keeplofi*)    ;;
        *)              HVM_Destroy_Diskvol $HVMlofi ;;
    esac
}

function img_version {
    typeset root="${1?altroot}"; shift

    awk -F= '$1 == "VERSION" {
        gsub(/[a-z]/, "")
        print $2
        }' $root/etc/os-release
}

function img_install_pkg {
    typeset root="${1?altroot}"; shift

    log "...installing packages: $*"

    # In case we are preparing a pre-release, temporarily add staging
    typeset ver=`img_version $root`
    if (( ver % 2 == 0 )); then
        pkg -R $root set-publisher \
            -g https://pkg.omnios.org/r$ver/staging omnios || true
    fi
    # Setting this flag lets `pkg` know that this is an automatic install and
    # that the installed packages should not be marked as 'manually installed'
    export PKG_AUTOINSTALL=1
    logcmd pkg -R $root install "$@"
    if (( ver % 2 == 0 )); then
        pkg -R $root set-publisher \
            -G https://pkg.omnios.org/r$ver/staging omnios || true
    fi
}

function img_install_profile {
    typeset root="${1?altroot}"; shift
    typeset profile="${1?profile}"; shift

    logcmd cp $profile $root/etc/svc/profile/site/
}

function img_permit_rootlogin {
    typeset root="${1?altroot}"; shift
    typeset type="${2:-without-password}"; shift

    log "...setting PermitRootLogin=$type in sshd_config"

    sed -i -e "s%^PermitRootLogin.*%PermitRootLogin $type%" \
        $root/etc/ssh/sshd_config
}

function img_postboot_block {
    typeset root="${1?altroot}"; shift

    while read line; do
        log "Postboot - '$line'"
        echo "$line" >> $root/.initialboot
    done
}

function img_serial_console {
    typeset root="${1?altroot}"; shift

    log "...enabling serial console"

    cat << EOM > $root/boot/conf.d/serial
console="ttya"
os_console="ttya"
ttya-mode="115200,8,n,1,-"
EOM
    printf "%s" "-h" > $root/boot/config
}

function img_dedicated_home {
    typeset root="${1?altroot}"; shift

    img_postboot_block $root << EOM
/sbin/zfs destroy -r rpool/export
/sbin/zfs create -o mountpoint=/home rpool/home
/bin/chmod 0555 /home
/usr/sbin/useradd -D -b /home
EOM
}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
