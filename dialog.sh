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

# Copyright 2018 OmniOS Community Edition (OmniOSce) Association.

if [ -x /kayak/dialog ]; then
	export USE_DIALOG=1
	export DIALOGRC=/kayak/dialog.rc
	export DIALOGRELEASE="`head -1 /etc/release`"

	dialog()
	{
		/kayak/dialog \
			--backtitle "$DIALOGRELEASE" \
			"$@"
	}

	d_info()
	{
		var="$*"
		typeset width=${#var}
		((width += 5))
		dialog --infobox "$@" 3 $width
	}

	d_msg()
	{
		var="$*"
		lines=5
		[[ "$var" = *\\n* ]] && lines=6
		typeset width=${#var}
		((width += 5))
		dialog --msgbox "$@" $lines $width
	}

	d_centre()
	{
		line="$1"
		cols="${2:-79}"

		printf "%*s" $(((cols + ${#line})/2)) "$line"
	}
fi

