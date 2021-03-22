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

# Copyright 2021 OmniOS Community Edition (OmniOSce) Association.

function hypervisor {
    cpuid | grep '^Hypervisor vendor string:' | cut -d"'" -f2
}

function vm_vmware {
    log "Installing open-vm-tools package..."
    runpkg install --no-refresh --no-index \
        -g /.cdrom/image/p5p/vmware.p5p open-vm-tools
    cp /kayak/etc/vmware.xml $ALTROOT/etc/svc/profile/site/
}

function vm_azure {
    log "Installing azure package..."
    runpkg install --no-refresh --no-index \
        -g /.cdrom/image/p5p/azure.p5p azure-agent
    cp /kayak/etc/azure.xml $ALTROOT/etc/svc/profile/site/
    sed -i '/^MANAGE_ZFS=NO/s/^/#/' $ALTROOT/etc/default/useradd
    sed -i '/^#MANAGE_ZFS=YES/s/#//' $ALTROOT/etc/default/useradd
    {
		echo "/sbin/zfs destroy -r $RPOOL/export"
		echo "/sbin/zfs create -o mountpoint=/home $RPOOL/home"
		echo "chmod 0555 /home"		# as per SUNWcs
		echo "/usr/sbin/useradd -D -b /home"
    } >> $ALTROOT/.initialboot
}

function setupvm {
    case `hypervisor` in
        bhyve*)     ;;
        KVM*)       ;;
        VMware*)    vm_vmware ;;
        Microsoft*) ;;
    esac
}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
