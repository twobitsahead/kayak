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

check_hostname() {
	echo $1 | egrep -s '^[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9]$'
}

t_prompt_hostname() {
	NEWHOST="$1"
	while [ -n "$NEWHOST" ]; do
		HOSTNAME="$NEWHOST"
		echo -n "Please enter a hostname or press RETURN if you want [$HOSTNAME]: "
		read NEWHOST
		[ -z "$NEWHOST" ] && break
		check_hostname "$NEWHOST" && continue
		echo "Invalid hostname - $NEWHOST"
		NEWHOST=$HOSTNAME
	done
}

d_prompt_hostname() {
	HOSTNAME="$1"
	while :; do
		dialog \
			--title "Enter the system hostname" \
			--inputbox '' 7 40 "$HOSTNAME" 2> $tmpf
		[ $? -ne 0 ] && exit 0
		HOSTNAME="`cat $tmpf`"
		rm -f $tmpf
		[ -z "$HOSTNAME" ] && continue
		check_hostname "$HOSTNAME" && break
		d_msg "Invalid hostname"
	done
}

prompt_hostname() {
	[ -n "$USE_DIALOG" ] && d_prompt_hostname "$@" || t_prompt_hostname "$@"
}

t_prompt_timezone() {
	tzselect |& tee /tmp/tz.$$
	TZ="`tail -1 /tmp/tz.$$`"
	rm -f /tmp/tz.$$
}

d_prompt_timezone() {
	# Select a timezone.
	/kayak/installer/dialog-tzselect /tmp/tz.$$
	TZ="`tail -1 /tmp/tz.$$`"
	rm -f /tmp/tz.$$
}

prompt_timezone() {
	[ -n "$USE_DIALOG" ] && d_prompt_timezone "$@" || t_prompt_timezone "$@"
}

