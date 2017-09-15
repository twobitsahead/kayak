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
# Copyright 2017 OmniOS Community Edition (OmniOSce) Association.
#

ALTROOT=/mnt
INITIALBOOT=$ALTROOT/.initialboot
IPCALC=/kayak/ipcalc
PASSUTIL=/kayak/passutil

debug=0
[ "$1" != '-t' ] && trap "" TSTP INT TERM ABRT QUIT || debug=1

dmsg()
{
	[ $debug -eq 1 ] && echo "$@"
}

pause()
{
	echo
	echo "$@"
	echo
	echo "Press return to continue...\\c"
	read a
}

ask()
{
	typeset a=

	while [[ "$a" != [yYnN] ]]; do
		echo "$* (y/n) \\c"
		read a
	done
	[[ "$a" = [yY] ]]
}

show_menu()
{
	nameref menu="$1"
	typeset title="${2:-configuration}"
	typeset -i input

	# Display the menu.
	stty sane
	clear

	defaultchoice=
	printf "Welcome to the OmniOSce $title menu\n\n"
	for i in "${!menu[@]}"; do
		nameref item=menu[$i]
		printf "\t%d  %-40s" "$((i + 1))" "${item.menu_str}"
		[ -n "${item.current}" ] && printf "[`${item.current}`]"
		printf "\n"
		[ -n "${item.default}" ] && defaultchoice=$((i + 1))
	done
	# Return to previous menu should be the default choice.
	[ -z "$defaultchoice" ] && defaultchoice=$((i + 1))

	# Take an entry (by number). If multiple numbers are
	# entered, accept only the first one.
	input=""
	dummy=""
	print -n "\nPlease enter a number [$defaultchoice]: "
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

	for j in "${!item.cmds[@]}"; do
		[ "${item.cmds[$j]}" = 'back' ] && return 1
		${item.cmds[$j]}
	done
}

remove_config()
{
	typeset tag=$1
	if [ -f $INITIALBOOT ]; then
		sed -i "/BEGIN_$tag/,/END_$tag/d" $INITIALBOOT
		[ -s $INITIALBOOT ] || rm -f $INITIALBOOT
	fi
}

##############################################################################
# Networking

save_networking()
{
	remove_config NETWORK
	[ -n "$net_if" ] || return
	[ "$net_ifmode" = "static" -a -z "$net_ip" ] && return
	(
		echo '### BEGIN_NETWORK'
		echo "/sbin/ipadm create-if $net_if"
		if [ "$net_ifmode" = "static" ]; then
			echo "/sbin/ipadm create-addr -T static"\
			    "-a local=$net_ip $net_if/v4"
			[ -n "$net_gw" ] && \
			    echo "echo $net_gw > /etc/defaultrouter"
		else
			echo "/sbin/ipadm create-addr -T dhcp $net_if/dhcp"
		fi
		if [ -n "$net_dns" ]; then
			echo '/bin/rm -f /etc/resolv.conf'
			[ -n "$net_domain" ] && \
			    echo "echo domain $net_domain >> /etc/resolv.conf"
			echo "echo nameserver $net_dns >> /etc/resolv.conf"
			echo '/bin/cp /etc/nsswitch.{dns,conf}'
		fi
		echo '### END_NETWORK'
	) >> $INITIALBOOT
}

load_networking()
{
	net_if=
	net_ifmode=
	net_ip=
	net_gw=
	net_domain=
	net_dns=
	if [ -f $INITIALBOOT ]; then
		net_if=`grep create-if $INITIALBOOT | cut -d\  -f3`
		if egrep -s -- '-T static' $INITIALBOOT; then
			net_ifmode=static
			net_ip=`grep create-addr $INITIALBOOT | cut -d\  -f6 \
			    | cut -d= -f2`
			net_gw=`grep defaultrouter $INITIALBOOT | cut -d\  -f2`
		fi
		egrep -s -- '-T dhcp' $INITIALBOOT && net_ifmode=dhcp
		net_domain=`grep '^echo domain' $INITIALBOOT | cut -d\  -f3`
		net_dns=`grep '^echo nameserver' $INITIALBOOT | cut -d\  -f3`
	fi
	# Some sensible defaults
	[ -z "$net_ifmode" ] && net_ifmode=static
	[ -z "$net_if" ] \
	    && net_if="`/sbin/dladm show-phys -p -o link | head -1`"
	[ -z "$net_dns" ] && net_dns=80.80.80.80
}

show_networking()
{
	if [ ! -f $INITIALBOOT ]; then
		echo '<Unconfigured>'
	elif egrep -s -- '-T static' $INITIALBOOT; then
		echo 'Static'
	elif egrep -s -- '-T dhcp' $INITIALBOOT; then
		echo 'DHCP'
	else
		echo '<Unconfigured>'
	fi
}

cfg_interface()
{
	echo

	cat <<- EOM

-- The folowing network interfaces have been found on this system.
-- Select the interface which should be configured.

	EOM

	i=0
	/sbin/dladm show-phys | while read line; do
		if [ $i -eq 0 ]; then
			printf "   $line\n"
		else
			printf "%2d %s\n" $i "$line"
			link=`echo $line | awk '{print $1}'`
			[ "$link" = "$net_if" ] && default=$i
		fi
		((i = i + 1))
	done

	echo

	while :; do
		read "_i?Network Interface [$default]: "
		[ -z "$_i" ] && break

		_net_if=`/sbin/dladm show-phys -p -o link | sed -n "${_i}p"`
		if [ -z "$_net_if" ]; then
			echo "No such interface, $_net_if"
			continue
		fi
		net_if="$_net_if"
		break
	done
}

show_interface()
{
	echo $net_if
}

cfg_ifmode()
{
	if [ "$net_ifmode" = "static" ]; then
		net_ifmode=dhcp
	else
		net_ifmode=static
	fi
}

show_ifmode()
{
	if [ "$net_ifmode" = "dhcp" ]; then
		echo "DHCP"
	else
		net_ifmode=static
		echo "Static"
	fi
}

cfg_ipaddress()
{
	if [ "$net_ifmode" != "static" ]; then
		pause "IP address will be retrieved via DHCP"
		return
	fi
	cat <<- EOM

-- Enter the IP address as <ip>/<netmask> or <ip>/<prefixlen>.
-- To remove the configured IP address, enter - by itself.
-- Examples:
--    10.0.0.2/255.255.255.224
--    10.0.0.2/27

	EOM

	while :; do
		read "_net_ip?IP Address [$net_ip]: "
		[ -z "$_net_ip" ] && break
		[ "$_net_ip" = "-" ] && net_ip= && net_gw= && break

		# Validate - ipcalc prints a useful message in the error case
		$IPCALC -c $_net_ip || continue

		typeset ip=${_net_ip%/*}
		typeset prefix=`$IPCALC -p $_net_ip | cut -d= -f2`
		[ "$prefix" = 32 ] && prefix=24
		typeset network=`$IPCALC -n $ip/$prefix | cut -d= -f2`
		typeset xcast=`$IPCALC -b $ip/$prefix | cut -d= -f2`

		[ "$ip" = "$network" ] \
		    && echo "Entered IP is the reserved network address." \
		    && continue
		[ "$ip" = "$xcast" ] \
		    && echo "Entered IP is the network broadcast address." \
		    && continue

		net_ip="$ip/$prefix"
		break
	done
}

show_ipaddress()
{
	[ "$net_ifmode" = "static" ] && echo $net_ip || echo "via DHCP"
}

cfg_gateway()
{
	if [ "$net_ifmode" != "static" ]; then
		pause "Gateway address will be retrieved via DHCP"
		return
	fi
	if [ -z "$net_ip" ]; then
		pause "Please set an IP address first"
		return
	fi

	cat <<- EOM

-- Enter the IP address of the default gateway.
-- To remove the configured gateway, enter - by itself.

	EOM

	while :; do
		read "_net_gw?Default Gateway [$net_gw]: "
		[ -z "$_net_gw" ] && break
		[ "$_net_gw" = "-" ] && net_gw= && break

		# Validate - ipcalc prints a useful message in the error case
		$IPCALC -c $_net_gw || continue

		typeset gwip=${_net_gw%/*}
		typeset ipprefix=`$IPCALC -p $net_ip | cut -d= -f2`
		typeset ipnetwork=`$IPCALC -n $net_ip | cut -d= -f2`
		typeset gwnetwork=`$IPCALC -n $gwip/$ipprefix | cut -d= -f2`

		[ "$ipnetwork" != "$gwnetwork" ] \
		    && echo "Gateway is not on the local network." \
		    && continue

		net_gw="$gwip"
		break
	done
}

show_gateway()
{
	[ "$net_ifmode" = "static" ] && echo $net_gw || echo "via DHCP"
}

cfg_domain()
{
	cat <<- EOM

-- Enter the DNS domain name.
-- To remove the configured domain, enter - by itself.

	EOM

	while :; do
		read "_net_domain?DNS Domain [$net_domain]: "
		[ -z "$_net_domain" ] && break
		[ "$_net_domain" = "-" ] && net_domain= && break

		if ! echo $_net_domain | /usr/xpg4/bin/egrep -q \
'^[a-z0-9-]{1,63}\.(xn--)?([a-z0-9]+(-[a-z0-9]+)*\.)*[a-z]{2,63}$'
		then
			echo "$_net_domain is not a valid domain name."
			continue
		fi
		net_domain="$_net_domain"
		break
	done
}

show_domain()
{
	echo $net_domain
}

cfg_dns()
{
	cat <<- EOM

-- Enter the IP address of the primary nameserver.
-- To remove the configured address, enter - by itself.

	EOM

	while :; do
		read "_net_dns?DNS Server [$net_dns]: "
		[ -z "$_net_dns" ] && break
		[ "$_net_dns" = "-" ] && net_dns= && break

		# Validate - ipcalc prints a useful message in the error case
		$IPCALC -c $_net_dns || continue

		# Remove any prefix that may have been entered in error
		net_dns=${_net_dns%/*}
		break
	done
}

show_dns()
{
	echo $net_dns
}

network_menu=( \
    (menu_str="Network Interface"					\
	cmds=("cfg_interface")						\
	current="show_interface"					\
    )									\
    (menu_str="Configuration Mode"					\
	cmds=("cfg_ifmode")						\
	current="show_ifmode"						\
    )									\
    (menu_str="IP Address"						\
	cmds=("cfg_ipaddress")						\
	current="show_ipaddress"					\
    )									\
    (menu_str="Default Gateway"						\
	cmds=("cfg_gateway")						\
	current="show_gateway"						\
    )									\
    (menu_str="DNS Domain"						\
	cmds=("cfg_domain")						\
	current="show_domain"						\
    )									\
    (menu_str="DNS Server"						\
	cmds=("cfg_dns")						\
	current="show_dns"						\
    )									\
    (menu_str="Return to main configuration menu"			\
	cmds=("save_networking" "back")							\
    )									\
)

cfg_networking()
{
	load_networking
	while show_menu network_menu "network configuration"; do
		:
	done
}

##############################################################################
# Create User

load_user()
{
	user_uid=
	user_pass=
	user_pfexec=
	user_sudo=
	user_sudo_nopw=
	if [ -f $INITIALBOOT ]; then
		user_uid=`grep useradd $INITIALBOOT | awk '{print $NF}'`
		user_sudo=`grep groupadd $INITIALBOOT | cut -d\  -f2`
		egrep -s 'Primary Admin' $INITIALBOOT && user_pfexec=y
		egrep -s 'NOPASSWD:' $INITIALBOOT && user_sudo_nopw=y
	fi
}

save_user()
{
	remove_config USER
	[ -z "$user_uid" ] && return
	(
		echo '### BEGIN_USER'
		echo "mkdir -p /export/home"
		echo "/usr/sbin/useradd -mZ -d /export/home/$user_uid $user_uid"
		echo "/usr/sbin/usermod -d /home/$user_uid $user_uid"
		echo "echo '$user_uid localhost:/export/home/&'"\
		    ">> /etc/auto_home"
		hash=`$PASSUTIL -H "$user_pass"`
		echo "sed -i 's|^$user_uid:[^:]*|$user_uid:$hash|' /etc/shadow"
		[ -n "$user_pfexec" ] && \
		    echo "/usr/sbin/usermod -P'Primary Administrator' $user_uid"
		if [ -n "$user_sudo" ]; then
			echo "/usr/sbin/groupadd $user_sudo"
			echo "/usr/sbin/usermod -G $user_sudo $user_uid"
			if [ -n "$user_sudo_nopw" ]; then
				echo "echo '%$user_sudo ALL=(ALL) "\
				    "NOPASSWD: ALL'"\
				    "> /etc/sudoers.d/group_$user_sudo"
			else
				echo "echo '%$user_sudo ALL=(ALL) ALL'"\
				    "> /etc/sudoers.d/group_$user_sudo"
			fi
		fi
		echo '### END_USER'
	) >> $INITIALBOOT
}

cfg_user()
{
	load_user

	if [ -n "$user_uid" ]; then
		cat <<- EOM

-- Choose a new username or to remove the user configuration, enter - at the
-- prompt.

		EOM
	fi

	while :; do
		read "_uid?Username [$user_uid]: "
		[ "$_uid" = "-" ] && user_uid= && break
		if [ -z "$_uid" ]; then
			[ -z "$user_uid" ] && break
			_uid=$user_uid
		fi

		if [[ ! $_uid =~ ^[a-z][-a-z0-9]*$ ]]; then
			echo "$_uid is not a valid username."
			continue
		fi
		user_uid=$_uid
		break
	done

	while :; do
		user_pass=
		while [ -z "$user_pass" ]; do
			stty -echo
			read "user_pass?Password: "
			echo
			stty echo
		done
		stty -echo
		read "user_pass2?   Again: "
		echo; stty echo

		if [ "$user_pass" != "$user_pass2" ]; then
			echo "-- Passwords do not match."
			continue
		fi
		break
	done

	cat <<- EOM

-- The new user can be automatically assigned to the Primary Administrator
-- role so that commands can be executed with root privileges via 'pfexec'

	EOM

	ask "Grant 'Primary Administrator' role to user?" \
	    && user_pfexec=y || user_pfexec=

	cat <<- EOM

-- If you wish, a new group can be created with access to sudo and the new
-- user can be placed into that group during installation.

	EOM

	if ask "Place user in new group and grant sudo?"; then
		[ -n "$user_sudo" ] && _default=$user_sudo || _default=sudo
		while :; do
			read "_grp?Group Name [$_default]: "
			if [ -z "$_grp" ]; then
				user_sudo=$_default
				break
			fi

			if [[ ! $_grp =~ ^[a-z][a-z]*$ ]]; then
				echo "$_grp is not a valid group name."
				continue
			fi

			user_sudo=$_grp
			break
		done
		ask "Require password for sudo?" \
		    && user_sudo_nopw= || user_sudo_nopw=y
	fi

	save_user
}

show_user()
{
	load_user
	tag='<none>'
	if [ -n "$user_uid" ]; then
		tag=$user_uid
	fi
	[ -n "$user_pfexec" ] && tag="$tag/admin"
	[ -n "$user_sudo" ] && tag="$tag/sudo"
	echo $tag
}

##############################################################################
# Set Root Password

cfg_rootpw()
{
	while :; do
		root_pass=
		while [ -z "$root_pass" ]; do
			stty -echo
			read "root_pass?Root Password: "
			echo; stty echo
		done
		stty -echo
		read "root_pass2?        Again: "
		echo; stty echo

		if [ "$root_pass" != "$root_pass2" ]; then
			echo "-- Passwords do not match."
			continue
		fi
		break
	done

	remove_config ROOTPW
	(
		echo "### BEGIN_ROOTPW"
		hash=`$PASSUTIL -H "$root_pass"`
		echo "sed -i 's|^root:[^:]*|root:$hash|' /etc/shadow"
		echo "### END_ROOTPW"
	) >> $INITIALBOOT

	pause "The root password has been set"
}

show_rootpw()
{
	[ -f $INITIALBOOT ] && egrep -s ROOTPW $INITIALBOOT \
	    && echo "********" || echo "<blank>"
}

##############################################################################
# Virtual Terminals

cfg_vtdaemon()
{
	if [ -f $INITIALBOOT ] && egrep -s vtdaemon $INITIALBOOT; then
		remove_config VTDAEMON
	else
		# Add configuration
		cat << EOM >> $INITIALBOOT
### BEGIN_VTDAEMON
/usr/sbin/svcadm enable vtdaemon
for i in \`seq 2 6\`; do
	/usr/sbin/svcadm enable console-login:vt\$i
done
/usr/sbin/svccfg -s vtdaemon setprop options/hotkeys=true
/usr/sbin/svccfg -s vtdaemon setprop options/secure=false
/usr/sbin/svcadm refresh vtdaemon
/usr/sbin/svcadm restart vtdaemon
### END_VTDAEMON
EOM
	fi
}

show_vtdaemon()
{
	[ -f $INITIALBOOT ] && egrep -s VTDAEMON $INITIALBOOT \
	    && echo "Enabled" || echo "Disabled"
}

##############################################################################
# SSH Server

cfg_sshd()
{
	if [ -f $ALTROOT/etc/svc/profile/site/nossh.xml ]; then
		rm -f $ALTROOT/etc/svc/profile/site/nossh.xml
	else
		[ -d  $ALTROOT/etc/svc/profile/site ] \
		    || mkdir -p  $ALTROOT/etc/svc/profile/site
		cp /kayak/nossh.xml $ALTROOT/etc/svc/profile/site/nossh.xml
	fi
}

show_sshd()
{
	[ -f $ALTROOT/etc/svc/profile/site/nossh.xml ] \
	    && echo "Disabled" || echo "Enabled"
}

##############################################################################

# Main menu
main_menu=( \
    (menu_str="Configure Networking"					\
	cmds=("cfg_networking")						\
	current="show_networking"					\
    )									\
    (menu_str="Create User"						\
	cmds=("cfg_user")						\
	current="show_user"						\
    )									\
    (menu_str="Set Root Password"					\
	cmds=("cfg_rootpw")						\
	current="show_rootpw"						\
    )									\
    (menu_str="SSH Server"						\
	cmds=("cfg_sshd")						\
	current="show_sshd"						\
    )									\
    (menu_str="Virtual Terminals"					\
	cmds=("cfg_vtdaemon")						\
	current="show_vtdaemon"						\
    )									\
    (menu_str="Return to main menu"					\
	cmds=("exit")							\
    )									\
)

while show_menu main_menu configuration; do
	:
done

