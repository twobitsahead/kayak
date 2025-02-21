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

# Copyright 2023 OmniOS Community Edition (OmniOSce) Association.

# This library used by both ksh and bash scripts, don't use any bash extensions.

OOCEVER=25.02 # `awk -F= '$1 == "VERSION" { print $2 }' /etc/os-release`
OOCEREL= # "${OOCEVER//[a-z]/}"

OOCEPUB=surya
EXTRAPUB=twobitsahead

URLPREFIX=http://209.38.51.159

MIRRORS=us-west
MIRRORDOMAIN=http://209.38.51.159

if (( OOCEREL % 2 == 0 )); then
    URLSUFFIX=r$OOCEREL/core
else
    URLSUFFIX=bloody/core
fi
OOCEPUBURL=http://209.38.51.159
OOCEPUBURL_EXTRA=http://209.38.51.159

OOCEBRAICHURL=$URLPREFIX/bloody/braich

DEFPATH=/usr/bin:/usr/sbin:/sbin:/usr/gnu/bin
DEFSUPATH=$DEFPATH
EXTRAPATH=$DEFPATH
EXTRASUPATH=$DEFPATH

NATIVE_SVCCFG=usr/src/tools/proto/root_i386-nd/opt/onbld/bin/i386/svccfg

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
