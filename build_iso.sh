#!/usr/bin/bash

# {{{ CDDL HEADER
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
# }}}

#
# Copyright 2017 OmniTI Computer Consulting, Inc. All rights reserved.
# Copyright 2018 OmniOS Community Edition (OmniOSce) Association.
#

#
# Build an ISO installer using the Kayak tools.
#

if [ `id -u` != "0" ]; then
	echo "You must be root to run this script."
	exit 1
fi

if [ -z "$BUILDSEND_MP" ]; then
	echo "Using /rpool/kayak_image for BUILDSEND_MP"
	BUILDSEND_MP=/rpool/kayak_image
fi

FVERSION="`head -1 $BUILDSEND_MP/root/etc/release | awk '{print $3}'`"
[ -z "$VERSION" ] && VERSION="`echo $FVERSION | sed 's/[a-z]*$//g'`"
echo "Using version $VERSION..."

stage()
{
	echo "***"
	echo "*** $*"
	echo "***"
}

# Allow temporary directory override
: ${TMPDIR:=/tmp}

KAYAK_MINIROOT=$BUILDSEND_MP/miniroot.gz
ZFS_IMG=$BUILDSEND_MP/kayak_${VERSION}.zfs.bz2

[ ! -f $KAYAK_MINIROOT -o ! -f $ZFS_IMG ] && echo "Missing files." && exit 1

ISO_ROOT=$TMPDIR/iso_root
BA_ROOT=$TMPDIR/boot_archive

KAYAK_ROOT=$TMPDIR/miniroot.$$
KR_FILE=$TMPDIR/kr.$$
MNT=/mnt
BA_SIZE=225M
DST_ISO=$BUILDSEND_MP/${VERSION}.iso

#############################################################################
#
# The kayak mini-root is used for both the ISO root filesystem and for the
# miniroot that is loaded and mounted on / when booted.
#

set -o errexit

mkdir $KAYAK_ROOT
mkdir $ISO_ROOT

# Create a UFS lofi file and mount the UFS filesystem in $MNT. This will
# form the boot_archive for the ISO.

stage "Mounting source miniroot"
# Uncompress and mount the miniroot
gunzip -c $KAYAK_MINIROOT > $KR_FILE
LOFI_RPATH=`lofiadm -a $KR_FILE`
mount $LOFI_RPATH $KAYAK_ROOT

stage "Creating UFS image for new miniroot"
mkfile $BA_SIZE $BA_ROOT
LOFI_PATH=`lofiadm -a $BA_ROOT`
echo 'y' | newfs $LOFI_PATH
mount $LOFI_PATH $MNT

# Copy the files from the miniroot to the new miniroot...
sz=`du -sh $KAYAK_ROOT | awk '{print $1}'`
stage "Adding files to new miniroot"
tar -cf - -C $KAYAK_ROOT . | pv -s $sz | tar -xf - -C $MNT
# ...and to the ISO root
stage "Adding files to ISO root"
tar -cf - -C $KAYAK_ROOT . | pv -s $sz | tar -xf - -C $ISO_ROOT

# Clean-up
stage "Unmounting source miniroot"
umount $KAYAK_ROOT
rmdir $KAYAK_ROOT
lofiadm -d $LOFI_RPATH
rm $KR_FILE

# Place the full ZFS image into the ISO root so it does not form part of the
# boot archive (otherwise the boot seems to hang for several minutes while
# the miniroot is loaded)

stage "Adding ZFS image to ISO root"
mkdir -p $ISO_ROOT/image
pv $ZFS_IMG > $ISO_ROOT/image/`basename $ZFS_IMG`
# Create a file to indicate that this is the right volume set on which to
# find the image - see src/mount_media.c
echo $VERSION > $ISO_ROOT/.volsetid

# Put additional files into the boot-archive on $MNT, which is
# what will be / (via ramdisk) once the ISO is booted.

stage "Adding extra files to miniroot"

# Extra files
cp -p \
    takeover-console \
    ipcalc passutil mount_media nossh.xml \
    dialog dialog.rc dialog.sh utils.sh dialog-tzselect \
    kbd.list \
    $MNT/kayak/.

if [ -n "$REFRESH_KAYAK" ]; then
	# For testing, make sure files in miniroot are current
	for f in $MNT/kayak/*; do
		[ -f "$f" ] || continue
		echo "REFRESH $f"
		cp `basename $f` $MNT/kayak
	done
fi

cat <<EOF > $MNT/root/.bashrc
export PATH=/usr/bin:/usr/sbin:/sbin
export HOME=/root
EOF

# Have initialboot invoke an interactive installer.
cat <<EOF > $MNT/.initialboot
/kayak/takeover-console /kayak/kayak-menu.sh
exit 0
EOF
# Increase the timeout
SVCCFG_REPOSITORY=$MNT/etc/svc/repository.db \
    svccfg -s system/initial-boot setprop "start/timeout_seconds=86400"

# Refresh the devices on the miniroot.
devfsadm -r $MNT

#
# The ISO's miniroot is going to be larger than the PXE miniroot. To that
# end, some files not listed in the exception list do need to show up on
# the miniroot. Use PREBUILT_ILLUMOS if available, or the current system
# if not.
#
from_one_to_other() {
    dir=$1

    FROMDIR=/
    [ -n "$PREBUILT_ILLUMOS" -a -d $PREBUILT_ILLUMOS/proto/root_i386/$dir ] \
        && FROMDIR=$PREBUILT_ILLUMOS/proto/root_i386

    shift
    tar -cf - -C $FROMDIR/$dir ${@:-.} | tar -xf - -C $MNT/$dir
}

# Add from_one_to_other for any directory {file|subdir file|subdir ...} you need
from_one_to_other usr/share/lib/zoneinfo
from_one_to_other usr/share/lib/keytables
from_one_to_other usr/share/lib/terminfo
from_one_to_other usr/gnu/share/terminfo
from_one_to_other usr/sbin ping
from_one_to_other usr/bin netstat

######################################################################
# Configure the loader for the installer

# Splash screen - add release version to top of screen

sed < $ISO_ROOT/boot/forth/brand-omnios.4th \
    > $ISO_ROOT/boot/forth/brand-omniosi.4th "
	/\" *\\/.*brand\+/s/ \"/  @[32m$FVERSION@[m&/
"

cat <<EOF > $ISO_ROOT/boot/loader.conf.local
loader_menu_title="Welcome to the OmniOSce installer"
loader_brand="omniosi"
autoboot_delay=10
EOF

# Add option to boot from hard disk
cat << EOM > $ISO_ROOT/boot/menu.rc.local
set mainmenu_caption[6]="Boot from [H]ard Disk"
set mainmenu_command[6]="chain disk1:"
set mainmenu_keycode[6]=104
set mainansi_caption[6]="Boot from ^[1mH^[mard Disk"
EOM

######################################################################

#
# Okay, we've populated the new miniroot. Close it up and install it
# on $ISO_ROOT as the boot archive.
#
stage "Miniroot size"
df -h $MNT
stage "Unmounting boot archive image"
umount $MNT
lofiadm -d $LOFI_PATH
stage "Installing boot archive"
pv $BA_ROOT | gzip -9c > $ISO_ROOT/platform/i86pc/amd64/boot_archive.gz
ls -lh $ISO_ROOT/platform/i86pc/amd64/boot_archive.gz | awk '{print $5}'
digest -a sha1 $BA_ROOT \
    > $ISO_ROOT/platform/i86pc/amd64/boot_archive.hash
rm -f $BA_ROOT
stage "Removing unecessary files from ISO root"
rm -rf $ISO_ROOT/{usr,bin,sbin,lib,kernel}
stage "ISO root size: `du -sh $ISO_ROOT/.`"

# And finally, burn the ISO.
mkisofs -N -l -R -U -d -D \
	-o $DST_ISO \
	-b boot/cdboot \
	-c .catalog \
	-no-emul-boot \
	-boot-load-size 4 \
	-boot-info-table \
	-allow-multidot \
	-no-iso-translate \
	-cache-inodes \
	-V "OmniOSce $VERSION" \
	$ISO_ROOT

rm -rf $ISO_ROOT
stage "$DST_ISO is ready"
ls -lh $DST_ISO

# Vim hints
# vim:fdm=marker
