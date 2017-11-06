#!/bin/bash
#
# CDDL HEADER START
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
# CDDL HEADER END
#
# Copyright 2013 by Andrzej Szeszo. All rights reserved.
# Copyright 2013 OmniTI Computer Consulting, Inc.  All rights reserved.
# Copyright 2017 OmniOS Community Edition (OmniOSce) Association.
# Use is subject to license terms.
#

[ "`id -u`" != 0 ] && echo Run this script as root && exit 1

. install_help.sh 2>/dev/null
. net_help.sh
. xen_help.sh

set -e

VERSION=`head -1 /etc/release | awk '{print $3}' | sed 's/[a-z]//g'`
ZFSSEND=/kayak_image/kayak_r$VERSION.zfs.bz2
PVGRUB=pv-grub.gz.d3950d8

RPOOL=syspool
BENAME=omnios
ALTROOT=/mnt
UNIX=/platform/i86xpv/kernel/amd64/unix

[ -f "$ZFSSEND" ] || ZFSSEND="omniosce-r$VERSION.zfs.bz2"
[ ! -f $ZFSSEND ] && echo "ZFS Image ($ZFSSEND) missing" && exit 

# Find the disk

DISK="`diskinfo -pH | grep -w 8589934592 | awk '{print $2}'`"
[ -z "$DISK" ] && echo "Cannot find 8GiB disk" && exit 1
cat << EOM

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

`diskinfo`

If you continue, disk $DISK will be completely erased

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

EOM
echo "Using disk $DISK...return to continue, ^C to abort...\\c"
read a

if [ ! -f $PVGRUB ]; then
	wget https://downloads.omniosce.org/media/misc/pv-grub.gz.d3950d8
fi

# Begin

zpool destroy $RPOOL 2>/dev/null || true

SetupPart
SetupPVGrub
SetupZPool
ZFSRecvBE

MountBE

# we need custom PV kernel because of this:
# https://www.illumos.org/issues/3172
if [ -f $UNIX ]; then
    cp $UNIX $ALTROOT/platform/i86xpv/kernel/amd64/unix
    chown root:sys $ALTROOT/platform/i86xpv/kernel/amd64/unix
fi

PrepareBE
ApplyChanges
SetTimezone UTC

Postboot '/sbin/ipadm create-if xnf0'
Postboot '/sbin/ipadm create-addr -T dhcp xnf0/v4'
Postboot 'for i in 0 1 2 3 4 5 6 7 8 9; do curl -f http://169.254.169.254/ >/dev/null 2>&1 && break; sleep 1; done'
Postboot 'HOSTNAME=$(/usr/bin/curl http://169.254.169.254/latest/meta-data/hostname)'
Postboot '[ -z "$HOSTNAME" ] || (/usr/bin/hostname $HOSTNAME && echo $HOSTNAME >/etc/nodename)'

UmountBE

zdb -C $RPOOL
zpool export $RPOOL

