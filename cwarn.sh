#!/bin/sh

optvars="
	'slaves:s:@path to file containing lines with ips and ports of the build slaves'
"

argvars="
	'url@url to ze source'
"

Main()
{
	rm -f in_garbage.c
	wget -nv -O in_garbage.c "$url"
	if ! [ -f in_garbage.c -a -s in_garbage.c ]; then
		E "this failed or gave something empty"
	fi

	printf '\n' >>in_garbage.c #swallowed at least on codepad

	if file in_garbage.c | grep 'HTML\|XML' >/dev/null; then
		E "this is HTML or XML"
	fi

	if ! file in_garbage.c | grep -iw 'text' >/dev/null; then
		E "this isn't text"
	fi


	if ! grep -F '}' in_garbage.c >/dev/null; then
		E "no brace, no C"
	elif ! grep -F '{' in_garbage.c >/dev/null; then
		E "no brace, no C"
	elif ! grep -F '(' in_garbage.c >/dev/null; then
		E "no parens, no C"
	elif ! grep -F ')' in_garbage.c >/dev/null; then
		E "no parens, no C"
	elif ! grep -F ';' in_garbage.c >/dev/null; then
		E "no semicolon, no C"
	fi

	jobs=$(mktemp /tmp/${prgnam}.XXXXXXXXX)

	# trim off potential trailing garbage
	lastbraceln=$(grep -Fn '}' in_garbage.c | tail -n1 | cut -d : -f 1)
	sed "${lastbraceln}q" in_garbage.c >$jobs #abuse the jobs tempfile temporarily
	cat <$jobs >in_garbage.c

	# if we can, trim potential leading garbage as well, this is even dumber a heuristic
	inclno=$(grep -n "^[ $TAB]*#" in_garbage.c | head -n1 | cut -d : -f 1)
	if [ -n "$inclno" ]; then
		if [ "$inclno" -gt 1 ]; then
			sed "1,$((inclno-1))d" in_garbage.c >$jobs #abuse the jobs tempfile temporarily
			cat <$jobs >in_garbage.c
		fi
	fi

	>$jobs

	D "seems legit on a first glance. dispatching to build slaves"

	for f in $(grep -v '^#' $slaves | grep -v "^[ $TAB]*\$" | sed 's/  */:/'); do
		host="$(echo "$f" | cut -d : -f 1)"
		port="$(echo "$f" | cut -d : -f 2)"
		res="res_$(printf '%s-%s' "$host" "$port")"
		printf 'BEGIN\n%s\nEND\n' "$(sed 's/^/DATA /' in_garbage.c)" >$tmp
		nc "$host" "$port" >"$res" <$tmp &
		printf '%s %s\n' "$!" "$res" >>$jobs
	done

	timeout=$(($(date +%s)+10))

	# no wait(1) here because we don't want to potentially wait forever
	while true; do
		if [ $(date +%s) -gt $timeout ]; then
			cut -d ' ' -f 1 $jobs | xargs kill -TERM 2>/dev/null
			break
		fi
	
		notfin=
		for pid in $(cut -d ' ' -f 1 $jobs); do
			if kill -s 0 $pid 2>/dev/null; then
				notfin=1
				break;
			fi
		done
	
		if [ -z "$notfin" ]; then
			break;
		fi

		sleep 1
	done

	rm -f r_*.res r_output in_garbage.c.lnum #ew. XXX

	export c=0
	cat $(cut -d ' ' -f 2 $jobs) | while read -r cmd rest; do
		case "$cmd" in
			BEGIN) c=$((c+1)); trg="r_${c}.res"; printf '%s\n' "$rest" >>$trg ;;
			DATA) printf '%s\n' "$rest" >>$trg ;;
			*) ;;
		esac
	done

	okay=0 nocomp=0 warnc=0 nolink=0 warnl=0 total=0
	for f in r_*.res; do
		status=$(head -n1 "$f" | cut -d ' ' -f 1)
		case "$status" in
			NOCOMPILE) nocomp=$((nocomp+1)) ;;
			WARNEDC) warnc=$((warnc+1)) ;;
			NOLINK) nolink=$((nolink+1)) ;;
			WARNEDL) warnl=$((warnl+1)) ;;
			OKAY) okay=$((okay+1)) ;;
		esac
		total=$((total+1))
	done

	#add line numbers the too-lazy-to-properly-learn-awk way
	export c=1

	printf '\n\n\n--------------------------------------------\n' >in_garbage.c.lnum
	printf 'Original program:\n\n' >>in_garbage.c.lnum
	sed 's/^/-/' in_garbage.c | while read -r ln; do
		printf '%s\t%s\n' $c "${ln#-}"
		c=$((c+1))
	done >>in_garbage.c.lnum
	printf '\n--------------------------------------------\n' >>in_garbage.c.lnum

	all="$( ( for f in r_*.res; do cat "$f"; printf '\n\n'; done ; cat in_garbage.c.lnum ) | curl -s -F 'sprunge=<-' http://sprunge.us)"

	if [ $okay -eq $total ]; then
		D "all good!"
		printf 'OKAY\n%s\n' "$all"
		exit 0 #everything great
	fi

	#don't be overly pedantic, some "testcases" lack a main
	if [ $((nocomp+warnc)) -eq 0 ]; then
		D "all semi-good!"
		printf 'OKAY\n%s\n' "$all"
		exit 0 #meh
	fi

	if [ $nocomp -gt 0 ]; then
		cand="$(GetBiggest NOCOMPILE)"
	elif [ $warnc -gt 0 ]; then
		cand="$(GetBiggest WARNEDC)"
	elif [ $nolink -gt 0 ]; then
		cand="$(GetBiggest NOLINK)"
	elif [ $warnl -gt 0 ]; then
		cand="$(GetBiggest WARNEDL)"
	else
		rm -f "$jobs"
		E "huh? $okay $nocomp $warnc $nolink $warnl $total"
	fi

	sed 1d "$cand" >r_output
	if ! [ -s r_output ] ; then
		rm -f "$jobs"
		E "output empty?"
	fi

	printf 'Info: %s\n' "$(head -n1 $cand)" >>in_garbage.c.lnum
	one="$(cat r_output in_garbage.c.lnum | curl -s -F 'sprunge=<-' http://sprunge.us)"

	printf '%s\n%s\n%s\n' "$(head -n1 $cand | cut -d ' ' -f 1)" "$one" "$all"
	rm -f "$jobs"

	return 0
}

GetBiggest()
{
	type="$1"
	set -x
	max=0
	cand=
	for f in $(grep -l "^$type" r_*.res); do
		nl=$(wc -l <$f)
		if [ $nl -gt $max ]; then
			max=$nl
			cand="$f"
		fi
	done
set +x

	printf '%s\n' "$cand"
}

prgauthor='Timo Buhrmester'
prgyear=2015
prgcontact='#fstd on irc.freenode.org'

#Available: D(), W(), E(), Usage()

. shboil.inc.sh
