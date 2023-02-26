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

OOCEVER=`awk -F= '$1 == "VERSION" { print $2 }' /etc/os-release`
OOCEREL="${OOCEVER//[a-z]/}"

OOCEPUB=omnios

if (( OOCEREL % 2 == 0 )); then
    OOCEPUBURL=https://pkg.omnios.org/r$OOCEREL/core
else
    OOCEPUBURL=https://pkg.omnios.org/bloody/core
fi
OOCEPUBURL_EXTRA="${OOCEPUBURL/core/extra}"

OOCEBRAICHURL=https://pkg.omnios.org/bloody/braich

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
