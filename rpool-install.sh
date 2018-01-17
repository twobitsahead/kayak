#!/usr/bin/bash

#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright 2017 OmniTI Computer Consulting, Inc. All rights reserved.
# Copyright 2018 OmniOS Community Edition (OmniOSce) Association.
#

RPOOL=${1:-rpool}
ZFS_IMAGE=/.cdrom/image/*.zfs.bz2
keyboard_layout=${2:-US-English}
tmpf=`mktemp`

[ -n "$USE_DIALOG" ] && . /kayak/dialog.sh
. /kayak/utils.sh

zpool list $RPOOL >& /dev/null
if [[ $? != 0 ]]; then
   echo "Cannot find root pool $RPOOL"
   echo "Press RETURN to exit"
   read
   exit 1
fi

echo "Installing from ZFS image $ZFS_IMAGE"

. /kayak/disk_help.sh
. /kayak/install_help.sh

prompt_hostname omniosce
prompt_timezone

# Because of kayak's small miniroot, just use C as the language for now.
LANG=C

BuildBE $RPOOL $ZFS_IMAGE
ApplyChanges $HOSTNAME $TZ $LANG $keyboard_layout
MakeBootable $RPOOL
# Disable SSH by default for interactive installations
[ -f /kayak/nossh.xml ] && cp /kayak/nossh.xml $ALTROOT/etc/svc/profile/site/
zpool list -v $RPOOL
echo ""
beadm list
cat << EOM

$RPOOL now has a working and mounted boot environment, per above.
Once back at the main menu, you can configure the initial system settings,
reboot, or enter the shell to modify your new BE before its first boot.

EOM
echo -n "Press RETURN to go back to the menu: "
read
