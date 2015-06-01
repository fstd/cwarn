#!/bin/sh

	#'indentflags:i:-bap -br -ce -ci4 -cli0 -d0 -di0 -i8 -ip -l79 -nbc -ncdb -ndj -ei -nfc1 -nlp -npcs -psl -sc -sob@indent flags'
optvars="
	'indentflags:i:-bap -br -ce -ci4 -cli0 -d0 -di0 -i8 -l79 -nbc -ncdb -ndj -nfc1 -nlp -npcs -psl -sc -sob@indent flags'
"

argvars="
	'url@url to ze source'
"

linux=
if [ "$(uname)" = "Linux" ] ; then
	linux=1
fi

Main()
{
	tmp=$(TF)
	res=/tmp/.repaste.tmp
	rm -f "$res"

	curl -s "$url" >"$tmp" 

	if ! [ -s "$tmp" ]; then
		W "Empty"
		exit 1
	fi

	if file "$tmp" | grep -q 'HTML\|XML'; then
		W "Markup"
		exit 1
	fi

	printf '\n' >>"$tmp" #swallowed at least on codepad
	tr -d '\r' <"$tmp" >"$res" #tendra chokes on \r\n endings as some pastebins produce

	ec=0
	if [ -n "$linux" ]; then
		icmd="indent $indentflags $res -o $tmp"
	else
		icmd="indent $indentflags $res $tmp"
	fi

	if $icmd >&2; then
		cat "$tmp" >"$res"
	else
		W "indent failed with $?"
		ec=2
	fi

	if ! r="$(pstd "$res")"; then
		W "pstd failed"
		exit 1
	fi

	printf '%s %s\n' "$r" "$res"

	return $ec;
}

prgauthor='Timo Buhrmester'
prgyear=2015
prgcontact='#fstd on irc.freenode.org'

#Available: D(), W(), E(), Usage()

. shboil.inc.sh
