#!/bin/ksh
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
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
#
# Copyright (c) 2009, 2011, Oracle and/or its affiliates. All rights reserved.
# Copyright 2017 OmniTI Computer Consulting, Inc. All rights reserved.
# Copyright 2017 OmniOS Community Edition (OmniOSce) Association.
#

# This started its life as the Caiman text-installer menu, hence the old
# OpenSolaris CDDL statement.

# LOGNAME variable is needed to display the shell prompt appropriately
export LOGNAME=root

# Block all signals which could terminate the menu or return to a parent process
debug=0
[ "$1" != '-t' ] && trap "" TSTP INT TERM ABRT QUIT || debug=1

dmsg()
{
	[ $debug -eq 1 ] && echo "$@"
}

# If an installation has been completed, there will be a boot environment
# and it will be mounted on /mnt
installed()
{
	[ -d /mnt/lib ] || return 1
	beadm list -H > /dev/null 2>&1
}

# Get the user's keyboard choice out of the way now.
/usr/bin/kbd -s
/usr/bin/loadkeys
# Remember it for configuration of final installed image.
ktype=`/usr/bin/kbd -l | grep '^type=' | cut -d= -f2`
layout=`/usr/bin/kbd -l | grep '^layout=' | cut -d= -f2 | awk '{print $1}'`
klang=`grep -w $layout /usr/share/lib/keytables/type_$ktype/kbd_layouts \
    | cut -d= -f1`

dmsg "klang = $klang"

# Define the menu of commands and prompts

# Preinstall menu
menu_items=( \
    (menu_str="Find disks, create rpool, and install OmniOSce"		\
	cmds=("/kayak/find-and-install.sh $klang")			\
	default="true"							\
	do_subprocess="true")						\
    (menu_str="Install OmniOSce straight on to a preconfigured rpool"	\
	cmds=("/kayak/rpool-install.sh rpool $klang")			\
	do_subprocess="true")						\
    (menu_str="Shell (for manual rpool creation)"			\
	cmds=("/usr/bin/bash")						\
	do_subprocess="true"						\
	msg_str="To return to the main menu, exit the shell")		\
    # this string gets overwritten every time $TERM is updated
    (menu_str="Terminal type (currently ""$TERM)"			\
	cmds=("prompt_for_term_type")					\
	do_subprocess="false")						\
    (menu_str="Reboot"							\
	cmds=("/usr/sbin/reboot")					\
	do_subprocess="true"						\
	noreturn="true"							\
	msg_str="Restarting, please wait...")				\
    (menu_str="Halt"							\
	cmds=("/sbin/beadm umount /mnt" "/sbin/uadmin 2 6")		\
	do_subprocess="true"						\
	noreturn="true"							\
	msg_str="Halting system, please wait...")			\
)

# Postinstall menu
pi_menu_items=( \
    (menu_str="Configure the installed OmniOS system"			\
	cmds=("/kayak/config-menu.sh")					\
	do_subprocess="true")						\
    (menu_str="Shell (for post-install ops on /mnt)"			\
	cmds=("/usr/bin/bash")						\
	do_subprocess="true"						\
	msg_str="To return to the main menu, exit the shell")		\
    (menu_str="Reboot"							\
	cmds=("/usr/sbin/reboot")					\
	do_subprocess="true"						\
	noreturn="true"							\
	msg_str="Restarting, please wait...")				\
    (menu_str="Halt"							\
	cmds=("/sbin/beadm umount /mnt" "/sbin/uadmin 2 6")		\
	do_subprocess="true"						\
	noreturn="true"							\
	default="true"							\
	msg_str="Halting system, please wait...")			\
)

# Update the menu_str for the terminal type
# entry. Every time the terminal type has been
# updated, this function must be called.
function update_term_menu_str
{
    # update the menu string to reflect the current TERM
    for i in "${!menu_items[@]}"; do
	    if [ "${menu_items[$i].cmds[0]}" = "prompt_for_term_type" ]; then
		menu_items[$i].menu_str="Terminal type (currently $TERM)"
	    fi
    done
}

# Set the TERM variable as follows:
#
# Just set it to "sun-color" for now.
#
function set_term_type
{
    export TERM=sun-color
    update_term_menu_str
}

# Prompt the user for terminal type
function prompt_for_term_type
{
	integer i

	# list of suggested termtypes
	typeset termtypes=(
		typeset -a fixedlist
		integer list_len        # number of terminal types
	)

	# hard coded common terminal types
	termtypes.fixedlist=(
		[0]=(  name="sun-color"		desc="PC Console"           )
		[1]=(  name="xterm"		desc="xterm"		    )
		[2]=(  name="vt100"		desc="DEC VT100"	    )
	)

	termtypes.list_len=${#termtypes.fixedlist[@]}

	# Start with a newline before presenting the choices
	print
	printf "Indicate the type of terminal being used, such as:\n"

	# list suggested terminal types
	for (( i=0 ; i < termtypes.list_len ; i++ )) ; do
		nameref node=termtypes.fixedlist[$i]
		printf "  %-10s %s\n" "${node.name}" "${node.desc}"
	done

	print
	# Prompt user to select terminal type and check for valid entry
	typeset term=""
	while true ; do
		read "term?Enter terminal type [$TERM]: " || continue

		# if the user just hit return, don't set the term variable
		[ -z "${term}" ] && return
			
		# check if the user specified option is valid
		term_entry=`/usr/bin/ls /usr/gnu/share/terminfo/*/$term \
		    2> /dev/null`
		[ -n "${term_entry}" ] && break
		echo
		echo "Terminal type not supported."
		echo "Supported terminal types can be found by using the"
		echo "shell to list the contents of /usr/gnu/share/terminfo."
		echo
	done

	export TERM="${term}"
	update_term_menu_str
}

set_term_type

while :; do
	# Display the menu.
	stty sane
	clear

	# Pick the right menu
	installed && nameref menu=pi_menu_items || nameref menu=menu_items

	printf "Welcome to the OmniOSce installation menu\n\n"
	for i in "${!menu[@]}"; do
		nameref item=menu[$i]
		print "\t$((i + 1))  ${item.menu_str}"
		[ -n "${item.default}" ] && defaultchoice=$((i + 1))
	done

	# Take an entry (by number). If multiple numbers are
 	# entered, accept only the first one.
	input=""
	dummy=""
	print -n "\nPlease enter a number [${defaultchoice}]: "
	read input dummy 2>/dev/null

	# If no input was supplied, select the default option
	[ -z "${input}" ] && input=$defaultchoice

	# Choice must only contain digits
	if [[ ${input} =~ [^1-9] || ${input} > ${#menu[@]} ]]; then
		continue
	fi

	# Re-orient to a zero base.
	((input = input - 1))

	nameref item=menu[$input]

	# Launch commands as a subprocess.
	# However, launch the functions within the context 
	# of the current process.
	if [[ "${item.do_subprocess}" = "true" ]]; then
		(
		trap - TSTP INT TERM ABRT QUIT
		# Print out a message if requested
		[ -n "${item.msg_str}" ] && printf "%s\n" "${item.msg_str}"
		for j in "${!item.cmds[@]}"; do
			${item.cmds[$j]}
		done
		)
	else
		# Print out a message if requested
		[ -n "${item.msg_str}" ] && printf "%s\n" "${item.msg_str}"
		for j in "${!item.cmds[@]}"; do
			${item.cmds[$j]}
		done
	fi

	if [[ "${item.noreturn}" = "true" ]]; then
		while :; do
			sleep 10000
		done
	fi
done

