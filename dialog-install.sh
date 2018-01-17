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

. /kayak/dialog.sh

keyboard_layout=${1:-US-English}

tmpf=`mktemp`

# In a KVM, the disks don't show up on the first invocation of diskinfo.
# More investigation required so, for now, run it twice.
diskinfo >/dev/null

diskinfo -H | tr "\t" "^" > $tmpf.disks
if [ ! -s $tmpf.disks ]; then
	d_msg "No disks found!"
	exit 0
fi

declare -a args=()
# SCSI    c0t0d1  SEAGATE ST300MP0005      279.40 GiB     no      no
#   -     c2t0d0  Virtio  Block Device     300.00 GiB     no      no
exec 3<$tmpf.disks
while read line <&3; do
	dev="`echo $line | cut -d^ -f2`"
	vid="`echo $line | cut -d^ -f3`"
	pid="`echo $line | cut -d^ -f4`"
	size="`echo $line | cut -d^ -f5`"
	option=`printf "%-20s %s" "$vid $pid" "$size"`

	args+=("$dev" "$option" off)
done
exec 3<&-

while :; do
	dialog \
		--title "Select disks for installation" \
		--colors \
		--checklist "\nSelect disks using arrow keys and space bar.\nIf you select multiple disks, you will be able to choose a RAID level on the next screen.\n\Zn" \
		0 0 0 \
		"${args[@]}" 2> $tmpf

	[ $? -ne 0 ] && exit 0

	DISKLIST="`cat $tmpf`"
	rm -f $tmpf
	if [ -z "$DISKLIST" ]; then
		d_msg "No disks selected"
		continue
	fi
	break
done

reality_check() {
	mkfile 64m /tmp/test.$$
	if [ $? != 0 ]; then
		[ -f /tmp/test.$$ ] && rm -f /tmp/test.$$
		echo "WARNING: Insufficient space in /tmp for installation..."
		return 1
	fi
	zpool create $1 /tmp/test.$$
	if [ $? != 0 ]; then
		echo "Can't test zpool create $1"
		rm -f /tmp/test.$$
		return 1
	fi
	zpool destroy $1
	rm -f /tmp/test.$$
	return 0
}

# Pool RAID level
ztype=
typeset -i ndisks="`echo $DISKLIST | wc -w`"
if [ "$ndisks" -gt 1 ]; then
	ztype=mirror

	typeset -a args=()

	args+=(stripe "Striped (no redundancy)" off)
	args+=(mirror "${ndisks}-way mirror" on)
	[ "$ndisks" -ge 3 ] && args+=(raidz "raidz  (single-parity)" off)
	[ "$ndisks" -ge 4 ] && args+=(raidz2 "raidz2 (dual-parity)" off)
	[ "$ndisks" -ge 5 ] && args+=(raidz3 "raidz3 (triple-parity)" off)

	dialog \
	    --title "RAID level" \
	    --colors \
	    --default-item $ztype \
	    --radiolist "\nSelect the desired pool configuration\n\Zn" \
	    12 50 0 \
	    "${args[@]}" 2> $tmpf
	[ $? -ne 0 ] && exit 0
	ztype="`cat $tmpf`"
	rm -f $tmpf
fi
[ "$ztype" = "stripe" ] && ztype=

RPOOL=rpool
while :; do
	dialog \
		--title "Enter the root pool name" \
		--colors \
		--inputbox '\nThis is the name of the ZFS pool that will be created using the selected disks and used for the OmniOS installation.\n\nThe default name is \Z7rpool\Zn and should usually be left unchanged.\n\Zn' \
		16 40 "$RPOOL" 2> $tmpf
	[ $? -ne 0 ] && exit 0
	RPOOL="`cat $tmpf`"
	rm -f $tmpf
	[ -z "$RPOOL" ] && continue
	if zpool list -H -o name | egrep -s "^$RPOOL\$"; then
		dialog --defaultno --yesno \
		    "\nPool already exists, overwrite?" 7 50
		[ $? = 0 ] || continue
		dialog --defaultno --yesno \
		    "\nConfirm destruction of existing pool?" 7 50
		[ $? = 0 ] || continue
		d_info "Destroying pool..."
		zpool destroy $RPOOL >/dev/null 2>&1
	fi
	d_info "Checking system..."
	reality_check $RPOOL && break
	d_msg "Invalid root pool name"
done

ztype=
[[ $DISKLIST = *\ * ]] && ztype=mirror
d_info "Creating $RPOOL..."
if zpool create -f $RPOOL $ztype $DISKLIST; then
	if zpool list $RPOOL >& /dev/null; then
		d_info "Successfully created $RPOOL..."
	else
		d_msg "Failed to create root pool"
		exit 0
	fi
else
	d_msg "Failed to create root pool"
	exit 0
fi

###########################################################################
# Prompt for hostname

HOSTNAME=omniosce
while :; do
	dialog \
		--title "Enter the system hostname" \
		--inputbox '' 7 40 "$HOSTNAME" 2> $tmpf
	[ $? -ne 0 ] && exit 0
	HOSTNAME="`cat $tmpf`"
	rm -f $tmpf
	[ -z "$HOSTNAME" ] && continue
	if echo $HOSTNAME | egrep -s '^[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9]$'
	then
		break
	else
		d_msg "Invalid hostname"
	fi
done

. /kayak/install_help.sh
. /kayak/disk_help.sh

# Select a timezone.
/kayak/dialog-tzselect /tmp/tz.$$
TZ=`tail -1 /tmp/tz.$$`
rm -f /tmp/tz.$$

ZFS_IMAGE=/.cdrom/image/*.zfs.bz2
echo "Installing from ZFS image $ZFS_IMAGE"

# Because of kayak's small miniroot, just use C as the language for now.
LANG=C

BuildBE $RPOOL $ZFS_IMAGE
ApplyChanges $HOSTNAME $TZ $LANG $keyboard_layout
MakeBootable $RPOOL
# Disable SSH by default for interactive installations
[ -f /kayak/nossh.xml ] && cp /kayak/nossh.xml $ALTROOT/etc/svc/profile/site/

if beadm list -H omnios 2>/dev/null; then
	dialog \
		--colors \
		--title "Installation Complete" \
		--msgbox "\\n\
`beadm list | sed 's/$/\\\\n/'`\\n\
$RPOOL now has a working and mounted boot environment, per above.\\n\
\\n\
Once back at the main menu, you can configure the initial system settings,\\n\
reboot, or enter the shell to modify your new BE before its first boot.\\n\\Zn\
" 0 0
else
	d_msg "Installation has failed.\\nCheck $INSTALL_LOG for more information."
fi

