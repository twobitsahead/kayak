#
# {{{ CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License, Version 1.0 only
# (the "License").  You may not use this file except in compliance
# with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://www.opensolaris.org/os/licensing.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END }}}
#
# Copyright 2013 by Andrzej Szeszo. All rights reserved.
#
# Copyright 2013 OmniTI Computer Consulting, Inc.  All rights reserved.
# Copyright 2017 OmniOS Community Edition (OmniOSce) Association.
# Use is subject to license terms.
#

log() {
    echo "$*"
}

SetupPVPart() {
    log "Setting up partition table on /dev/rdsk/${DISK}p0" 

    cat <<EOF | fdisk -F /dev/stdin /dev/rdsk/${DISK}p0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0
EOF

    NUMSECT=`iostat -En $DISK|nawk '
	/^Size:/ { sub("<",""); print $3/512 - 34816 }'`

    fdisk -A 6:0:0:0:0:0:0:0:2048:32768 /dev/rdsk/${DISK}p0
    fdisk -A 191:0:0:0:0:0:0:0:34816:$NUMSECT /dev/rdsk/${DISK}p0
}

CreateSlice0() {
    disks -C

    prtvtoc -h /dev/rdsk/${DISK}p0  > /tmp/xenparts

    # Create partition 0 which will be used for the zpool
    prtvtoc -h /dev/rdsk/${DISK}p0 | nawk '
	BEGIN		{ p=0 }
	# Record the size of partition 2 (entire disk)
	$1 == "2"	{ size = $5; p = 1 }
	# Record the size of partition 8 (boot)
	$1 == "8"	{ start = $5; p = 1 }
	p == 1		{ print $1, $2, $3, $4, $5 }
	END		{
				size = size - start
				# Create partiton 0
				print "0 2 00", start, size
			}
	' | sort -n | tee -a /tmp/xenparts \
	  | fmthard -s - /dev/rdsk/${DISK}s2

    disks -C
}

SetupHVMPart() {
    # Use an SMI label for HVM images
    log "Setting up partition table on /dev/rdsk/${DISK}p0" 

    # Single 'solaris2' partition
    fdisk -B /dev/rdsk/${DISK}p0
    CreateSlice0
}

SetupPVGrub() {

    log "Setting up 16MB FAT16 pv-grub filesystem"

    echo y|mkfs -F pcfs -o b=pv-grub /dev/rdsk/${DISK}p0:c
    mount -F pcfs /dev/dsk/${DISK}p1 $ALTROOT
    cp $PVGRUB $ALTROOT/pv-grub.gz
    mkdir -p $ALTROOT/boot/grub

    cat <<EOF >$ALTROOT/boot/grub/menu.lst
timeout 0
default 0
title chainload pv-grub
root (hd0,0)
kernel /pv-grub.gz (hd0,1,a)/boot/grub/menu.lst
EOF

    umount $ALTROOT
}

SetupPVZPool() {

    log "Setting up '${RPOOL}' zpool"

    # Re-install slice 8 to create a VTOC (fdisk will have erased it)
    prtvtoc -h /dev/rdsk/c4t0d0s2 | \
	awk '$1 == 8 {print}' | fmthard -s - /dev/rdsk/${DISK}s2

    CreateSlice0

    zpool create -f ${RPOOL} /dev/dsk/${DISK}s0
}

Grub_MakeBootable() {
    # GRUB stuff
    echo "BE_HAS_GRUB=true" > $ALTROOT/etc/default/be
    log "...setting up GRUB and the BE"
    mkdir -p /${RPOOL}/boot/grub/bootsign
    touch /${RPOOL}/boot/grub/bootsign/pool_${RPOOL}
    chown -R root:root /${RPOOL}/boot
    chmod 444 /${RPOOL}/boot/grub/bootsign/pool_${RPOOL}

    RELEASE=`head -1 $ALTROOT/etc/release | awk '{print $3}'`

    cat <<EOF >/${RPOOL}/boot/grub/menu.lst
default 0
timeout 3

title ${RELEASE}
findroot (pool_${RPOOL},0,a)
bootfs ${RPOOL}/ROOT/${BENAME}
kernel$ /platform/i86pc/kernel/amd64/unix -B \$ZFS-BOOTFS
module$ /platform/i86pc/amd64/boot_archive
#============ End of LIBBE entry =============
EOF

    zpool set bootfs=${RPOOL}/ROOT/${BENAME} ${RPOOL}

    log "Activate"
    beadm activate -v $BENAME
    $ALTROOT/boot/solaris/bin/update_grub -R $ALTROOT
    bootadm update-archive -R $ALTROOT
}

Xen_Customise() {
    # Allow root to ssh in
    log "...setting PermitRootLogin=yes in sshd_config"
    sed -i -e 's%^PermitRootLogin.*%PermitRootLogin without-password%' \
	    $ALTROOT/etc/ssh/sshd_config
    
    # Set up to use DNS
    log "...enabling DNS resolution"
    SetDNS 1.1.1.1 80.80.80.80

    # Install ec2-credential and ec2-api-tools packages.
    # rsync needed for vagrant
    log "...installing EC2 and rsync packages"
    pkg -R $ALTROOT install network/rsync ec2-credential ec2-api-tools

    # Remove disk links so they will be correctly generated on first boot.
    rm -f $ALTROOT/dev/dsk/* $ALTROOT/dev/rdsk/*
    touch $ALTROOT/reconfigure

    # Decrease boot delay
    cat << EOM > $ALTROOT/boot/loader.conf.local
autoboot_delay=1
EOM
}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
