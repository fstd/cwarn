# 2014, Timo Buhrmester
# occasionally useful shell script boilerplate

_boil_trace=false
if [ "$1" = "-X" ]; then
	shift
	set -x
elif [ "$1" = "-x" ]; then
	shift
	_boil_trace=true
fi
_boil_argv=; while [ $# -gt 0 ]; do _boil_argv="${_boil_argv}'$1' "; shift; done
eval "set -- $_boil_argv"

_boil_verb=0
_boil_prgnam=$(basename "$0")
_boil_traplist="$(mktemp /tmp/${_boil_prgnam}.XXXXXXXXX)"
_boil_gentraplist="$(mktemp /tmp/${_boil_prgnam}.XXXXXXXXX)"
trap '_boil_Cleanup' EXIT

TAB="$(printf "\t")"
_boil_NL='
'
_boil_arg_num_opt=0
_boil_arg_num_mand=0

prgauthor="${prgauthor:-Nobody}"
prgyear="${prgyear:-Never}"
prgcontact="${prgcontact:-'Do not call us, we call you'}"

V() { if [ $_boil_verb -gt 1 ]; then printf '%s: %s: %s\n' "$_boil_prgnam" "$(date)" "$*" >&2; fi; }
D() { if [ $_boil_verb -gt 0 ]; then printf '%s: %s: %s\n' "$_boil_prgnam" "$(date)" "$*" >&2; fi; }
W() { printf '%s: %s: %s\n' "$_boil_prgnam" "$(date)" "$*" >&2; }
E() { printf '%s: %s: %s\n' "$_boil_prgnam" "$(date)" "$*" >&2 ; exit 1; }

Verbosity()
{
	printf '%s\n' $_boil_verb
}

_boil_Init()
{
	_boil_Init_Optvars
	_boil_Init_Argvars
	while getopts "hv$_boil_getopt_optstr" _boil_i; do
		if [ "$_boil_i" = "?" ]; then _boil_Usage; fi

		_boil_optnam=
		eval "_boil_optnam=\"\$_boil_optnam_$_boil_i\""
		eval "_boil_hasarg=\"\$_boil_optarg_$_boil_i\""
		if [ -n "$_boil_optnam" ]; then
			if [ -n "$_boil_hasarg" ]; then
				eval "${_boil_optnam}='$OPTARG'"
			else
				eval "${_boil_optnam}='$_boil_i'"
			fi
		else
			case "$_boil_i" in
			v) _boil_verb=$((_boil_verb+1)) ;;
			*) _boil_Usage ;;
			esac
		fi
	done

	shift $(expr $OPTIND - 1)

	if [ $# -lt $_boil_arg_num_mand ]; then
		W "too few arguments (need at least $_boil_arg_num_mand)" >&2
		_boil_Usage
		exit 1
	fi

	for _boil_f in $(printf "%s\n" "$_boil_uah_mand" | tr -d '<>'); do
		eval "${_boil_f}='$1'"
		shift
	done

	for _boil_f in $(printf "%s\n" "$_boil_uah_opt" | tr -d '[<>]'); do
		if [ $# -eq 0 ]; then
			break;
		fi

		eval "${_boil_f}='$1'"
		shift
	done

	for _boil_f in $_boil_optnams; do
		_boil_oldifs="$IFS"
		IFS=':'
		set -- ${_boil_f}_
		IFS="$_boil_oldifs"

		eval "$_boil_f=\"\${$_boil_f:-\$_boil_DEF_$_boil_f}\""
	done
}


_boil_Init_Optvars()
{
	_boil_getopt_optstr=''

	# Iterate over the optvar entries defined at the top
	eval "set -- $(printf "%s\n" "$optvars" | tr -d '\n')"
	while [ $# -gt 0 ]; do
		_boil_entry="$1"
		shift

		_boil_usg_descr="${_boil_entry#*@}"
		_boil_entry="${_boil_entry%%@*}"

		# We need the function call to backup the positional parameters
		_boil_Init_Optvars_Core "$_boil_entry" #assigns _boil_optnam, _boil_go_chr, _boil_optval_def, _boil_go_hasarg
		_boil_optnams="${_boil_optnams}$_boil_optnam "

		_boil_getopt_optstr="${_boil_getopt_optstr}${_boil_go_chr}${_boil_go_hasarg}"
		eval "_boil_optnam_${_boil_go_chr%:}='$_boil_optnam'"
		eval "_boil_optarg_${_boil_go_chr%:}='$_boil_go_hasarg'"
		eval "_boil_usage=\"\${_boil_usage}    -$(printf "%s\n" "$_boil_go_chr$_boil_go_hasarg" \
		    | sed 's/:$/ <arg>/'): $_boil_usg_descr$_boil_NL\""

		eval "unset $_boil_optnam; _boil_DEF_$_boil_optnam='$_boil_optval_def' ; $_boil_optnam="
	done
}

_boil_Init_Optvars_Core()
{
	_boil_oldifs="$IFS"
	IFS=':'
	set -- ${1}_ #add trailing colon to 'preserve' potential trailing delim
	IFS="$_boil_oldifs"

	_boil_optnam="$1"
	_boil_go_chr="$2"
	_boil_go_hasarg=
	_boil_optval_def=

	if [ $# -gt 2 ]; then
		shift; shift
		while [ $# -gt 0 ]; do 
			_boil_optval_def="$_boil_optval_def:$1"
			shift
		done
		_boil_optval_def="${_boil_optval_def%_}"
		_boil_optval_def="${_boil_optval_def#:}"
		_boil_go_hasarg=":"
	else
		_boil_go_chr="${_boil_go_chr%_}"
	fi
}

_boil_Init_Argvars()
{
	# Iterate over the argvar entries defined at the top
	eval "set -- $(printf "%s\n" "$argvars" | tr -d '\n')"
	while [ $# -gt 0 ]; do
		_boil_entry="$1"
		shift

		_boil_usg_descr="${_boil_entry#*@}"
		_boil_entry="${_boil_entry%%@*}"

		# We need the function call to backup the positional parameters
		_boil_Init_Argvars_Core "$_boil_entry" #assigns _boil_argnam, _boil_argopt

		if [ -n "$_boil_argopt" ]; then
			_boil_uah_opt="${_boil_uah_opt}[<$_boil_argnam>] "
			_boil_arg_num_opt=$((_boil_arg_num_opt+1))
		else
			_boil_uah_mand="${_boil_uah_mand}<$_boil_argnam> "
			_boil_arg_num_mand=$((_boil_arg_num_mand+1))
		fi

		eval "_boil_argusage=\"\${_boil_argusage}    $(printf "%s\n" "<$_boil_argnam>$_boil_argopt" \
		    | sed 's/:$/ (optional)/'): $_boil_usg_descr$_boil_NL\""
		eval "unset $_boil_argnam; $_boil_argnam="
	done
}

_boil_Init_Argvars_Core()
{
	_boil_oldifs="$IFS"
	IFS=':'
	set -- ${1}_ #add trailing colon to 'preserve' potential trailing delim
	IFS="$_boil_oldifs"

	_boil_argnam="${1%_}"
	if [ -n "$2" ]; then
		_boil_argopt=:
	fi
}

_boil_Usage()
{
	printf "Usage: %s [ -%svh ] %s %s\n" "$_boil_prgnam" "$_boil_getopt_optstr" "$_boil_uah_mand" "$_boil_uah_opt" >&2
	printf "  Options:\n" >&2
	printf "%s" "$_boil_usage" >&2
	printf "    -v: Be more verbose\n" >&2
	printf "    -h: Display this usage statement\n" >&2
	printf "  Arguments:\n" >&2
	printf "%s" "$_boil_argusage" >&2
	printf "(C) %s, %s (contact: %s)\n" "$prgyear" "$prgauthor" "$prgcontact" >&2
	exit 1
}

# Hand out filenames of new temp files, arrange for them to be removed on exit
TF()
{
	_boil_tmp="$(mktemp /tmp/${_boil_prgnam}.XXXXXXXXX)"
	#if given an argument (regardless what it is), don't automatically rm on exit
	if [ $# -eq 0 ]; then
		printf '%s\n' "$_boil_tmp" | tee -a "$_boil_traplist"
	else
		printf '%s\n' "$_boil_tmp"
	fi
}

AddTrap()
{
	printf '%s\n' "$1" >>$_boil_gentraplist
}

_boil_Cleanup()
{
	# Remove the accumulated tempfiles
	# only some basic sanity check here because someone with the right
	# permissions might inject filenames into the traplist
	cat "$_boil_traplist" | grep -F "/tmp/${_boil_prgnam}." | while read -r _boil_ln; do
		rm -f "$_boil_ln"
	done
	rm -f "$_boil_traplist";

	cat "$_boil_gentraplist" | while read -r ln; do
		D "evaling '$ln'"
		eval "$ln"
	done
	rm -f "$_boil_gentraplist";
}

eval "set -- $_boil_argv"
_boil_Init "$@"
if $_boil_trace; then
	set -x
fi
Main "$@"
exit $?
