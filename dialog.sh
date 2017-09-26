
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
fi

