#!/bin/sh

optvars="
	'cmpl:c:@comma separated list of colon separated compiler,switches pairs'
"

argvars="
	'host@host/address to bind to'
	'port@port to listen on'
"

Main()
{
	tmp_accum=$(mktemp /tmp/${prgnam}_accum.XXXXXXXXX)
	tmp_fifo="${tmp_accum}.fifo"

	while true; do
		rm -f "$tmp_fifo"
		if ! mkfifo "$tmp_fifo"; then
			rm -f "$tmp_accum"
			E "failed to mkfifo '$tmp_fifo'";
		fi

		cat "$tmp_fifo" | ncat -l $host $port | while read -r cmd rest; do
			case $cmd in
			BEGIN) >$tmp_accum ; ;;
			DATA) printf '%s\n' "$rest" >>$tmp_accum ;; #data line
			END) D "$(date): received a chunk"
				cat "$tmp_accum" >garbage.c
				Build garbage.c >"$tmp_fifo" ;;
			*) W "dunno wat do with '$tmp' '$rest'" ;;
			esac
		done

		sleep 1 #rate limit just in case
	done

	rm -f "$tmp_accum" "$tmp_fifo"

	return 0
}

BuildWith()
{
	src="$1"
	cc="$2"
	sw="$3"

	tmp_err_c=$(mktemp /tmp/${prgnam}_out.XXXXXXXXX)
	tmp_err_l=$(mktemp /tmp/${prgnam}_out.XXXXXXXXX)

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
	ccver=$($cc --version | head -n1 | sed 's/ /_/g')

	printf 'BEGIN %s %s %s %s\n' $retstr $platform "$ccver" "$sw"
	#this sucks, see above too
	if [ -s $tmp_err_c ]; then
		sed 's/^/DATA /' $tmp_err_c
	elif [ -s $tmp_err_l ]; then
		sed 's/^/DATA /' $tmp_err_l
	fi
	printf 'END\n'

	rm -f "$tmp_err_c" "$tmp_err_l"
}

Build()
{
	src="$1"

	oldifs="$IFS"
	IFS=,
	set -- $cmpl
	IFS="$oldifs"

	while [ $# -gt 0 ]; do
		cc="$(echo "$1" | cut -d ':' -f 1)"
		sw="$(echo "$1" | sed 's/^[^:]*://')"
		shift
		BuildWith "$src" "$cc" "$sw"
	done
}

prgauthor='Timo Buhrmester'
prgyear=2015
prgcontact='#fstd on irc.freenode.org'

#Available: D(), W(), E(), Usage()

. shboil.inc.sh
