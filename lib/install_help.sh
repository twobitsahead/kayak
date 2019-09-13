#!/usr/bin/bash

# {{{ CDDL licence header
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
# }}}

#
# Copyright 2017 OmniTI Computer Consulting, Inc.  All rights reserved.
# Copyright 2019 OmniOS Community Edition (OmniOSce) Association.
#

LOG_SETUP=0

SetupLog() {
    if [ "$LOG_SETUP" -eq 0 ]; then
        INSTALL_LOG=${1}
        LOG_SETUP=1
        exec 4>>${1}
    fi
}

ConsoleLog() {
    if [ "$LOG_SETUP" -eq 0 ]; then
        exec 4>/dev/console
        exec 1>>${1}
        exec 2>>${1}
        INSTALL_LOG=${1}
        LOG_SETUP=1
    fi
}

OutputLog() {
    if [ "$LOG_SETUP" -eq 0 ]; then
        exec 4>/dev/null
        LOG_SETUP=1
    fi
}

CopyInstallLog() {
    if [ -n "$INSTALL_LOG" ]; then
        cp $INSTALL_LOG $ALTROOT/var/log/install/kayak.log
    fi
}

SendInstallLog() {
    PUTURL=`echo $CONFIG | sed -e 's%/kayak/%/kayaklog/%g;'`
    PUTURL=`echo $PUTURL | sed -e 's%/kayak$%/kayaklog%g;'`
    curl -T $INSTALL_LOG $PUTURL/$ETHER
}

log() {
    OutputLog
    TS=`date +%Y/%m/%d-%H:%M:%S`
    echo "[$TS] $*" 1>&4
    echo "[$TS] $*"
}

pipelog() {
    tee -a $INSTALL_LOG
}

slog() {
    if [ -n "$USE_DIALOG" ]; then
        TS=`date +%Y/%m/%d-%H:%M:%S`
        echo "[$TS] $*" 1>&4
        d_info "$@"
    else
        log "$@"
    fi
}

bomb() {
    log
    log ======================================================
    log "$*"
    log ======================================================
    if [[ -n "$INSTALL_LOG" ]]; then
        log "For more information, check $INSTALL_LOG"
        log ======================================================
    fi
    exit 1
}

. /kayak/lib/net_help.sh
. /kayak/lib/disk_help.sh

ICFILE=/tmp/_install_config
getvar(){
  prtconf -v /devices | sed -n '/'$1'/{;n;p;}' | cut -f2 -d\'
}

# Blank
ROOTPW='$5$kr1VgdIt$OUiUAyZCDogH/uaxH71rMeQxvpDEY2yX.x0ZQRnmeb9'
RootPW(){
  ROOTPW="$1"
}
SetRootPW(){
  sed -i -e 's%^root::%root:'$ROOTPW':%' $ALTROOT/etc/shadow
}
ForceDHCP(){
  log "Forcing all interfaces into DHCP..."
  /sbin/ifconfig -a plumb 2> /dev/null
  # for the logs
  for iface in `/sbin/dladm show-phys -o device -p` ; do
    /sbin/ifconfig $iface dhcp &
  done
  while [[ -z $(/sbin/dhcpinfo BootSrvA) ]]; do
    log "Waiting for dhcpinfo..."
    sleep 1
  done
  BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
  log "Next server: $BOOTSRVA"
  sleep 1
}

BE_Create_Root() {
    local _rpool="${1:?rpool}"

    [ -z "$NO_COMPRESSION" ] && zfs set compression=on $_rpool
    zfs create $_rpool/ROOT
    # The miniroot does not have any libshare SMF services so the following
    # commands print an error.
    (
        zfs set canmount=off $_rpool/ROOT
        zfs set mountpoint=legacy $_rpool/ROOT
    ) 2>&1 | grep -v 'libshare SMF'
}

BE_Receive_Image() {
    local _grab="${1:?grab}"
    local _decomp="${2:?decomp}"
    local _rpool="${3:?rpool}"
    local _bename="${4:?bename}"
    local _media="${5:?media}"

    slog "Preparing to install ZFS image"
    pv="pv -B 128m"
    [ "$_grab" = cat ] && pv+=" -s `ls -lh $_media | awk '{print $5}'`"

    if [ -n "$USE_DIALOG" ]; then
        ($_grab $_media | $pv -n | $_decomp \
            | zfs receive -u $_rpool/ROOT/$_bename) 2>&1 \
            | dialog --gauge 'Installing ZFS image' 7 70
    else
        $_grab $_media | $pv -w 78 | $_decomp | \
            zfs receive -u $_rpool/ROOT/$_bename 2>&4
    fi
    zfs set canmount=noauto $_rpool/ROOT/$_bename 1>&4 2>&4
    zfs set mountpoint=legacy $_rpool/ROOT/$_bename 1>&4 2>&4
}

BE_Mount() {
    local _rpool=${1:?rpool}
    local _bename=${2:?bename}
    local _root=${3:?root}
    local _method${4:-beadm}

    slog "Mounting BE $_bename on $_root"

    if [ "$_method" = beadm ]; then
        beadm mount $_bename $_root 1>&4 2>&4
    else
        mount -F zfs $_rpool/ROOT/$_bename $_root 1>&4 2>&4
    fi
    export ALTROOT=$_root
}

BE_Umount() {
    local _bename=${1:?bename}
    local _root=${2:?root}
    local _method${3:-beadm}

    slog "Unmounting BE $_bename"
    if [ "$_method" = beadm ]; then
        beadm umount $_bename 1>&4 2>&4
    else
        umount $_root 1>&4 2>&4
    fi
}

BE_SetUUID() {
    local _rpool=${1:?rpool}
    local _bename=${2:?bename}
    local _root=${3:?root}

    local uuid=`LD_LIBRARY_PATH=$_root/lib:$_root/usr/lib \
        $_root/usr/bin/uuidgen`

    slog "Setting BE $_bename UUID: $uuid"
    zfs set org.opensolaris.libbe:uuid=$uuid $_rpool/ROOT/$_bename 1>&4 2>&4
    zfs set org.opensolaris.libbe:policy=static $_rpool/ROOT/$_bename 1>&4 2>&4
}

BE_LinkMsglog() {
    local _root=${1:?root}

    /usr/sbin/devfsadm -r $_root 1>&4 2>&4
    [ -L "$_root/dev/msglog" ] || \
        ln -s ../devices/pseudo/sysmsg@0:msglog $_root/dev/msglog
}

BuildBE() {
    RPOOL=${1:-rpool}
    local MEDIA="$2"
    local _bename=${3:-omnios}

    if [ -z "$MEDIA" ]; then
        BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
        MEDIA=`getvar install_media`
        MEDIA=`echo $MEDIA | sed -e "s%//\:%//$BOOTSRVA\:%g;"`
        MEDIA=`echo $MEDIA | sed -e "s%///%//$BOOTSRVA/%g;"`
        GRAB="curl -s"
    else
        GRAB=cat
    fi
    DECOMP="bzip2 -dc"      # Old default
    case $MEDIA in
        *.xz)       DECOMP="xz -dc" ;;
        *.bz2)      DECOMP="bzip2 -dc" ;;
        *.gz)       DECOMP="gzip -dc" ;;
    esac

    BE_Create_Root $RPOOL
    BE_Receive_Image "$GRAB" "$DECOMP" $RPOOL $_bename $MEDIA
    BE_Mount $RPOOL $_bename /mnt
    BE_SetUUID $RPOOL $_bename /mnt
    BE_LinkMsglog /mnt
    MakeSwapDump
    Postboot "zpool set cachefile=/etc/zfs/zpool.cache $RPOOL"
    zfs destroy $RPOOL/ROOT/$_bename@kayak 1>&4 2>&4
}

FetchConfig(){
  ETHER=`Ether`
  BOOTSRVA=`/sbin/dhcpinfo BootSrvA`
  CONFIG=`getvar install_config`
  CONFIG=`echo $CONFIG | sed -e "s%//\:%//$BOOTSRVA\:%g;"`
  CONFIG=`echo $CONFIG | sed -e "s%///%//$BOOTSRVA/%g;"`
  L=${#ETHER}
  while [[ "$L" -gt "0" ]]; do
    URL="$CONFIG/${ETHER:0:$L}"
    log "... trying $URL"
    /bin/curl -s -o $ICFILE $URL
    if [[ -f $ICFILE ]]; then
      if [[ -n $(grep BuildRpool $ICFILE) ]]; then
        log "fetched config."
        return 0
      fi
      rm -f $ICFILE
    fi
    L=$(($L - 1))
  done
  return 1
}

MakeBootable(){
  local _rpool=${1:-rpool}
  local _bename=${2:-omnios}
  slog "Making boot environment bootable"
  zpool set bootfs=$_rpool/ROOT/$_bename $_rpool
  # Must do beadm activate first on the off chance we're bootstrapping from
  # GRUB.
  slog "Activating BE"
  beadm activate $_bename 2>/dev/null|| return 1
  slog "Installing bootloader"
  bootadm install-bootloader -Mf -P $_rpool || return 1
  slog "Updating boot archive"
  bootadm update-archive -R $ALTROOT || return 1
  return 0
}

SetHostname()
{
  log "Setting hostname: ${1}"
  /bin/hostname "$1"
  echo "$1" > $ALTROOT/etc/nodename
  sed -i '/^[^#]/d' $ALTROOT/etc/inet/hosts
  cat << EOM >> $ALTROOT/etc/inet/hosts
::1		localhost $1.local $1
127.0.0.1	localhost loghost $1.local $1
EOM
}

AutoHostname() {
  suffix=$1
  macadr=`/sbin/ifconfig -a | \
          /usr/bin/awk '/UP/{if($2 !~ /LOOPBACK/){iface=$1;}} /ether/{if(iface){print $2; exit;}}' | \
          /bin/tr '[:upper:]' '[:lower:]' | \
          /bin/sed -e 's/^/ 0/g;s/:/-0/g; s/0\([0-9a-f][0-9a-f]\)/\1/g; s/ //g;'`
  [ -z $suffix ] && suffix=omnios
  [ "$suffix" == "-" ] && suffix= || suffix=-$suffix
  SetHostname $macadr$suffix
}

SetTimezone()
{
  log "Setting timezone: ${1}"
  sed -i -e "s:^TZ=.*:TZ=${1}:" $ALTROOT/etc/default/init
}

SetLang()
{
  log "Setting language: ${1}"
  sed -i -e "s:^LANG=.*:LANG=${1}:" $ALTROOT/etc/default/init
}

SetKeyboardLayout()
{
      # Put the new keyboard layout ($1) in
      # "setprop keyboard-layout <foo>" in the newly-installed root's
      # /boot/solaris/bootenv.rc (aka. eeprom(1M) storage for amd64/i386).
      layout=$1
      sed -i "s/keyboard-layout Unknown/keyboard-layout $layout/g" \
          $ALTROOT/boot/solaris/bootenv.rc
      # Also modify the system/keymap service
      Postboot "/usr/sbin/svccfg -s system/keymap:default"\
         "setprop keymap/layout = '$layout'"
      Postboot "/usr/sbin/svcadm refresh system/keymap:default"
      Postboot "/usr/sbin/svcadm restart system/keymap:default"
}

ApplyChanges(){
  SetRootPW
  [[ -L $ALTROOT/etc/svc/profile/generic.xml ]] || \
    ln -s generic_limited_net.xml $ALTROOT/etc/svc/profile/generic.xml
  [[ -L $ALTROOT/etc/svc/profile/name_service.xml ]] || \
    ln -s ns_dns.xml $ALTROOT/etc/svc/profile/name_service.xml

  # Extras from interactive ISO/USB install...
  # arg1 == hostname
  if [[ ! -z $1 ]]; then
      SetHostname $1
  fi

  # arg2 == timezone
  if [[ ! -z $2 ]]; then
      SetTimezone $2
  fi

  # arg3 == Language
  if [[ ! -z $3 ]]; then
      SetLang $3
  fi

  # arg4 == Keyboard layout
  if [[ ! -z $4 ]]; then
      SetKeyboardLayout $4
  fi

  return 0
}

Postboot() {
  [[ -f $ALTROOT/.initialboot ]] || touch $ALTROOT/.initialboot
  echo "$*" >> $ALTROOT/.initialboot
}

Reboot() {
  # This is an awful hack... we already setup bootadm
  # and we've likely deleted enough of the userspace that this
  # can't run successfully... The easiest way to skip it is to
  # remove the binary
  rm -f /sbin/bootadm
  svccfg -s "system/boot-config:default" setprop config/fastreboot_default=false
  svcadm refresh svc:/system/boot-config:default
  reboot
}

RunInstall(){
  FetchConfig || bomb "Could not fetch kayak config for target"
  # Set RPOOL if it wasn't done so already. We need it set.
  RPOOL=${RPOOL:-rpool}
  . $ICFILE
  Postboot 'exit $SMF_EXIT_OK'
  ApplyChanges || bomb "Could not apply all configuration changes"
  MakeBootable $RPOOL || bomb "Could not make new BE bootable"
  log "Install complete"
  return 0
}

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
