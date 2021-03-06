#!/bin/sh

optvars="
	'cmpl:c:@comma separated list of colon separated std:compiler:switches pairs'
"

argvars="
	'host@host/address to bind to'
	'port@port to listen on'
"

Main()
{
	tmp_accum=$(TF)
	tmp_fifo="${tmp_accum}.fifo"

	while true; do
		rm -f "$tmp_fifo"
		mkfifo "$tmp_fifo" || E "failed to mkfifo '$tmp_fifo'"

		export std=
		cat "$tmp_fifo" | ncat -l $host $port | while read -r cmd rest; do
			case $cmd in
			BEGIN) >$tmp_accum ; std="$rest" ;;
			DATA) printf '%s\n' "$rest" >>$tmp_accum ;; #data line
			END) D "$(date): received a chunk"
				cat "$tmp_accum" >garbage.c
				Build garbage.c "$std" >"$tmp_fifo" ;;
			*) W "dunno wat do with '$tmp' '$rest'" ;;
			esac
		done

		sleep 1 #rate limit just in case
	done

	rm -f "$tmp_fifo"

	return 0
}

BuildWith()
{
	src="$1"
	cc="$2"
	sw="$3"

	tmp_err_c=$(TF)
	tmp_err_l=$(TF)

	$cc $sw -c "$src" >/dev/null 2>$tmp_err_c </dev/null
	compiled=$?
	$cc $sw -o /dev/null "$src" >/dev/null 2>$tmp_err_l </dev/null
	linked=$?

	# XXX not sure if this order is ideal
	retstr=OKAY
	if [ $compiled -ne 0 ]; then
		retstr=NOCOMPILE
	elif [ -s $tmp_err_c ]; then
		retstr=WARNEDC
	elif [ $linked -ne 0 ]; then
		retstr=NOLINK
	elif [ -s $tmp_err_l ]; then
		retstr=WARNEDL
	fi

	platform=$(uname -sm | sed 's/ /\//g')
	ver='--version'
	if [ "$cc" = 'tendracc' ]; then
		ver='-V'
	fi
	ccver=$($cc $ver 2>&1 | head -n1 | sed 's/ /_/g')

	printf 'BEGIN %s %s %s %s\n' $retstr $platform "$ccver" "$sw"
	#this sucks, see above too
	if [ -s $tmp_err_c ]; then
		sed 's/^/DATA /' $tmp_err_c
	elif [ -s $tmp_err_l ]; then
		sed 's/^/DATA /' $tmp_err_l
	fi
	printf 'END\n'
}

Build()
{
	src="$1"
	std="$2"

	oldifs="$IFS"
	IFS=,
	set -- $cmpl
	IFS="$oldifs"

	while [ $# -gt 0 ]; do
		c="$1"
		shift

		st="$(echo "$c" | cut -d ':' -f 1)"
		if ! [ "$st" = "$std" ]; then
			continue
		fi

		cc="$(echo "$c" | cut -d ':' -f 2)"
		sw="$(echo "$c" | sed 's/^[^:]*:[^:]*://')"

		BuildWith "$src" "$cc" "$sw"
	done
}

prgauthor='Timo Buhrmester'
prgyear=2015
prgcontact='#fstd on irc.freenode.org'

#Available: D(), W(), E(), Usage()

. shboil.inc.sh
