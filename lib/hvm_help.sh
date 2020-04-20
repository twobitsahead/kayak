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
# Copyright 2020 OmniOS Community Edition (OmniOSce) Association.
#

. $SRCDIR/../lib/install_help.sh 2>/dev/null
. $SRCDIR/../lib/disk_help.sh
. $SRCDIR/../lib/net_help.sh

# Override the log function
log() {
    [ "$1" = "-o" ] && shift
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

find_zfssend() {
	[ -z "$VERSION" ] && \
	    VERSION="`nawk 'NR == 1 { sub(/^r/, "", $3); print $3 }' \
	    /etc/release`"
	: ${ZFSSEND:=/kayak_image/kayak_r$VERSION.zfs.xz}
	[ -f "$ZFSSEND" ] || ZFSSEND="omniosce-r$VERSION.zfs.xz"
}

HVM_Image_Init() {
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

	SetupLog /tmp/kayak-$tag.log
}

HVM_Image_Build() {
	typeset poolopts="${1:?poolopts}"; shift
	typeset zfssend="${1:?zfssend}"; shift
	typeset hostname="${1:-omnios}"; shift
	typeset custom="$1"; shift

	echo "Clearing any old pool"
	zpool destroy -f $HVMtmprpool 2>/dev/null || true

	zpool create $poolopts \
	    -t $HVMtmprpool -m $HVMpoolmount $HVMrpool $HVMdisk

	BE_Create_Root $HVMtmprpool
	BE_Receive_Image cat "xz -dc" $HVMtmprpool $HVMbename $zfssend
	mkdir -p $HVMaltroot
	BE_Mount $HVMtmprpool $HVMbename $HVMaltroot raw
	BE_SetUUID $HVMtmprpool $HVMbename $HVMaltroot
	BE_LinkMsglog $HVMaltroot
	MakeBootable $HVMtmprpool $HVMbename
	ApplyChanges
	SetTimezone UTC
	echo $hostname > $HVMaltroot/etc/nodename

	# Any additional customisation
	[ -n "$custom" ] && $custom

	# Force new IPS UUID on first pkg invocation.
	sed -i '/^last_uuid/d' $HVMaltroot/var/pkg/pkg5.image

	# Move disk links so they will be correctly generated on first boot.
	rm -f $HVMaltroot/dev/dsk/* $HVMaltroot/dev/rdsk/*

	# Reconfigure on first boot
	touch $HVMaltroot/reconfigure

	#
	# First boot configuration
	#

	# Pools are deliberately created with no features enabled and then
	# updated on first boot to add all features supported on the target
	# system.
	Postboot 'zpool upgrade -a'
	# Give the pool a unique GUID
	Postboot "zpool reguid $RPOOL"
}

HVM_Image_Finalise() {
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
		*-keeplofi*)	;;
		*)		HVM_Destroy_Diskvol $HVMlofi ;;
	esac
}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
