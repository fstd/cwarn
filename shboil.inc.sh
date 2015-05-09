# 2014, Timo Buhrmester
# occasionally useful shell script boilerplate

if [ "$1" = "-x" ]; then shift; set -x; fi
argv=; while [ $# -gt 0 ]; do argv="${argv}'$1' "; shift; done
eval "set -- $argv"

verbose=0
prgnam=$(basename "$0")
tmp=$(mktemp /tmp/${prgnam}.XXXXXXXXX)
trap "rm -f '${tmp}'" EXIT
TAB="$(printf "\t")"
NL='
'
arg_num_opt=0
arg_num_mand=0

prgauthor="${prgauthor:-Nobody}"
prgyear="${prgyear:-Never}"
prgcontact="${prgcontact:-'Do not call us, we call you'}"

D() { if [ $verbose -gt 0 ]; then echo "$prgnam: $*" >&2; fi; }
W() { echo "$prgnam: $*" >&2; } 
E() { echo "$prgnam: ERROR: $*" >&2 ; exit 1; }

Init()
{
	Init_Optvars
	Init_Argvars
	while getopts "hv$getopt_optstr" i; do
		if [ "$i" = "?" ]; then Usage; fi

		optnam=
		eval "optnam=\"\$optnam_$i\""
		eval "hasarg=\"\$optarg_$i\""
		if [ -n "$optnam" ]; then
			if [ -n "$hasarg" ]; then
				eval "${optnam}='$OPTARG'"
			else
				eval "${optnam}='$i'"
			fi
		else
			case "$i" in
			v) verbose=$((verbose+1)) ;;
			*) Usage ;;
			esac
		fi
	done

	shift $(expr $OPTIND - 1)

	if [ $# -lt $arg_num_mand ]; then
		W "too few arguments (need at least $arg_num_mand)" >&2
		Usage
		exit 1
	fi

	for f in $(echo "$uah_mand" | tr -d '<>'); do
		eval "${f}='$1'"
		shift
	done

	for f in $(echo "$uah_opt" | tr -d '[<>]'); do
		if [ $# -eq 0 ]; then
			break;
		fi

		eval "${f}='$1'"
		shift
	done

	for f in $optnams; do
		oldifs="$IFS"
		IFS=':'
		set -- ${f}_
		IFS="$oldifs"

		eval "$f=\"\${$f:-\$DEF_$f}\""
	done
}


Init_Optvars()
{
	getopt_optstr=''

	# Iterate over the optvar entries defined at the top
	eval "set -- $(echo "$optvars" | tr -d '\n')"
	while [ $# -gt 0 ]; do
		entry="$1"
		shift

		usg_descr="${entry#*@}"
		entry="${entry%%@*}"

		# We need the function call to backup the positional parameters
		Init_Optvars_Core "$entry" #assigns optnam, go_chr, optval_def, go_hasarg
		optnams="${optnams}$optnam "

		getopt_optstr="${getopt_optstr}${go_chr}${go_hasarg}"
		eval "optnam_${go_chr%:}='$optnam'"
		eval "optarg_${go_chr%:}='$go_hasarg'"
		eval "usage=\"\${usage}    -$(echo "$go_chr$go_hasarg" \
		    | sed 's/:$/ <arg>/'): $usg_descr$NL\""

		eval "unset $optnam; DEF_$optnam='$optval_def' ; $optnam="
	done
}

Init_Optvars_Core()
{
	oldifs="$IFS"
	IFS=':'
	set -- ${1}_ #add trailing colon to 'preserve' potential trailing delim
	IFS="$oldifs"

	optnam="$1"
	go_chr="$2"
	go_hasarg=
	optval_def=

	if [ $# -gt 2 ]; then
		optval_def="${3%_}"
		go_hasarg=":"
	else
		go_chr="${go_chr%_}"
	fi
}

Init_Argvars()
{
	# Iterate over the argvar entries defined at the top
	eval "set -- $(echo "$argvars" | tr -d '\n')"
	while [ $# -gt 0 ]; do
		entry="$1"
		shift

		usg_descr="${entry#*@}"
		entry="${entry%%@*}"

		# We need the function call to backup the positional parameters
		Init_Argvars_Core "$entry" #assigns argnam, argopt

		if [ -n "$argopt" ]; then
			uah_opt="${uah_opt}[<$argnam>] "
			arg_num_opt=$((arg_num_opt+1))
		else
			uah_mand="${uah_mand}<$argnam> "
			arg_num_mand=$((arg_num_mand+1))
		fi

		eval "argusage=\"\${argusage}    $(echo "<$argnam>$argopt" \
		    | sed 's/:$/ (optional)/'): $usg_descr$NL\""
		eval "unset $argnam; $argnam="
	done
}

Init_Argvars_Core()
{
	oldifs="$IFS"
	IFS=':'
	set -- ${1}_ #add trailing colon to 'preserve' potential trailing delim
	IFS="$oldifs"

	argnam="${1%_}"
	if [ -n "$2" ]; then
		argopt=:
	fi
}

Usage()
{
	echo "Usage: $prgnam [ -${getopt_optstr}vh ] $uah_mand $uah_opt" >&2
	echo "  Options:" >&2
	echo -n "$usage" >&2
	echo "    -v: Be more verbose" >&2
	echo "    -h: Display this usage statement" >&2
	echo "  Arguments:" >&2
	echo -n "$argusage" >&2
	echo "(C) $prgyear, $prgauthor (contact: $prgcontact)" >&2
	exit 1
}


eval "set -- $argv"
Init "$@"
Main "$@"
exit $?
