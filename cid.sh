#!/bin/sh

optvars="
	'cc:c:gcc@c compiler to use for guessing a standard'
"

argvars="
	'url@url to ze source'
	'out@target filename (saves prepared source as)'
"

Main()
{
	rm -f "$out"
	wget -nv -O "$out" "$url"
	if ! [ -f "$out" -a -s "$out" ]; then
		echo "BAD EMPTY"
		exit 0
	fi

	printf '\n' >>"$out" #swallowed at least on codepad

	if file "$out" | grep 'HTML\|XML' >/dev/null; then
		echo "BAD NOPLAIN"
		exit 0
	fi

	if ! grep -F '}' "$out" >/dev/null; then
		echo "BAD NOTC"
		exit 0
	elif ! grep -F '{' "$out" >/dev/null; then
		echo "BAD NOTC"
		exit 0
	elif ! grep -F '(' "$out" >/dev/null; then
		echo "BAD NOTC"
		exit 0
	elif ! grep -F ')' "$out" >/dev/null; then
		echo "BAD NOTC"
		exit 0
	elif ! grep -F ';' "$out" >/dev/null; then
		echo "BAD NOTC"
		exit 0
	fi

	jobs=$(mktemp /tmp/${prgnam}.XXXXXXXXX)

	# trim off potential trailing garbage
	lastbraceln=$(grep -Fn '}' "$out" | tail -n1 | cut -d : -f 1)
	sed "${lastbraceln}q" "$out" >$jobs #abuse the jobs tempfile temporarily
	cat <$jobs >"$out"

	# if we can, trim potential leading garbage as well, this is even dumber a heuristic
	inclno=$(grep -n "^[ $TAB]*#" "$out" | head -n1 | cut -d : -f 1)
	if [ -n "$inclno" ]; then
		if [ "$inclno" -gt 1 ]; then
			sed "1,$((inclno-1))d" "$out" >$jobs #abuse the jobs tempfile temporarily
			cat <$jobs >"$out"
		fi
	fi

	>$jobs

	std="$(GuessStd "$out")"

	main='NOMAIN'
	if grep -q "^[ $TAB]*\(int\|void\|\)[ $TAB]*main[ $TAB]*(" "$out"; then
		main='MAIN'
	fi

	D "I guess that is as '$std', '$main'"

	printf "%s %s\n" "$std" "$main"

	return 0
}

GuessStd()
{
	err=$(mktemp /tmp/${prgnam}.XXXXXX)
	src="$1"
	ret=DUNNO
	for e in 'c89 c99 c11' 'gnu89 gnu99 gnu11'; do
	for f in '-pedantic-errors' '-pedantic' ''; do
	for g in $e; do
		D "Trying $cc ($g, $f)"
		if $cc -std=$g $f -o /dev/null \
		    -c "$src" >/dev/null 2>$err </dev/null; then
			if [ "$g" = "c89" ] && grep -q 'mixed decl' $err; then
				# hack: mixed decl and code -> c99 even
				# though gcc accepts it in c89 mode
				continue
			fi

			ret="$g"
			break 3
		fi
	done
	done
	done

	echo "$ret" | sed 's/gnu/c/'
	rm -f "$err"
}

prgauthor='Timo Buhrmester'
prgyear=2015
prgcontact='#fstd on irc.freenode.org'

#Available: D(), W(), E(), Usage()

. shboil.inc.sh
