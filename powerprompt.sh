#!/bin/bash
# Filename:      powerprompt.sh
# Maintainer:    Jasper Boot <jasper.boot+powerprompt@gmail.com>

# Description: A powerfull prompt with the 'less is more principle' for colors
#              If nothing special is happening, prompt will be all uncolored
#              (currently only for Bash)
#
# Current Format: user@host:pwd [git section] [dynamic section]> 
# USER:
#   Black/Red == Root(UID 0) sudo shell (unwanted)
#   Red       == Root(UID 0) direct login shell
#   Light Red == Root(UID 0) indirect login shell (i.e. su -l or sudo su -)
#   Yellow    == Root(UID 0) privileges in non-root shell (i.e. su)
#   Brown     == SU to user other than root(UID 0)
#   Default   == Normal user
# @:
#   Red       == Insecure(?) connection (unknown type)
#   Cyan      == Insecure remote connection (eg Telnet/RSH)
#   Green     == Secure remote connection (i.e. SSH)
#   Default   == Local session
# HOST:
#   Black/Red == LoadAvg/#cores last 5 minutes >= 5.0
#   Red	      == LoadAvg/#cores last 5 minutes >= 1.0
#   Yellow    == LoadAvg/#cores last 5 minutes >= 0.7
#   Default   == LoadAvg/#cores last 5 minutes <  0.7
# GIT SECTION (only shows when git-completion is installed and when pwd is in a git repo)
#    (branch)    === Shows current git branch
# DYNAMIC SECTION
#    (Yellow; If count is zero for any of the following, it will not appear)
#    [scr:#]     === Number of detached screen sessions
#    [jobs:#/#]  === Number of running/stopped (backgrounded) jobs
# WORKING DIRECTORY:
#   Gray       == Current user does not have write priviledges
#   Default    == Current user does have write priviledges
#

# Only execute for interactive shells and only if this is bash
[[ "$-" != *i* ]] && return

###
# Utility functions
###

# Returns escape sequence for xterm title/icontext
_term_print()
{
	# Terminal escape codes: 
	# 0: /* new icon name and title*/
	# 1: /* new icon name only */
	# 2: /* new title only */
	case "$2" in
	TITLE)
		echo -en "\e]2;$1\a"
		;;
	ICON)
		echo -en "\e]1;$1\a"
		;;
	*)
		echo -en "\e]0;$1\a"
		;;
	esac
}

# Returns escape sequence for screen hardline status
_screenterm_print()
{
	echo -en "\e_$1\e\\";
}

# Shortens the first (if needed) and second (if needed) dir to 1 char
_pwd_slim()
{
	local _w=$1
	test -n "${_w}" || _w=${PWD}
	local pwdmaxlen=$2
	test -n ${pwdmaxlen} || pwdmaxlen=30
	if [[ "${_w:1:1}" != "~" ]]; then
		if [ ${#_w} -gt ${pwdmaxlen} ]; then
			_w="${_w:0:2}/${_w#/*/}";
		fi
		if [ ${#_w} -gt ${pwdmaxlen} ]; then
			_w="${_w:0:4}/${_w#/?/*/}";
		fi
	fi
	echo -n "${_w}"
}

# Truncs the start of string to make it fit into a set length
_pwd_trunc()
{
	local _w=$1
	test -n "${_w}" || _w=${PWD}
	local pwdmaxlen=$2
	test -n ${pwdmaxlen} || pwdmaxlen=30
	if [ ${#_w} -gt ${pwdmaxlen} ]; then
		local pwdoffset=$(( ${#_w} - ${pwdmaxlen} + ${#PP_PWD_ELLIPSIS} ))
		_w="${_w:$pwdoffset:$pwdmaxlen}"
		_w="${_w#*/}"
		_w="${PP_PWD_ELLIPSIS}${_w}"
	fi
	echo -n "${_w}"
}
	
###
# Function section with path-truncation functions
###

# Returns short path (last two directories; no home substitution) by openSUSE
spwd () 
{
	( 
		IFS=/
		set ${PWD}
		if test $# -le 3 ; then
			echo "${PWD}"
		else
			eval echo \"${PP_PWD_ELLIPSIS}\${$(($#-1))}/\${$#}\"
		fi 
	) ;
}

# Fish's default pwd (all but last directory down to 1 char per dir; with home substitution)
fishpwd()
{
	local _w="${PWD/$HOME/~}"
	echo -n "${_w}" | sed -e 's-/\([^/]\)\([^/]*\)-/\1-g'
	echo -n "${_w}" | sed -n -e 's-.*/.\([^/]*\)-\1-p'
	echo
}

# Powerprompt's default pwd (intelligent slimming; with home substitution)
powerpwd() 
{
	local pp_cols="${COLUMNS:-80}"
	local pwdmaxlen=$((${pp_cols}/3))
	local _w="${PWD/$HOME/~}"
	# If needed strip first (evt. second) dir down to one char
	_w=$(_pwd_slim "${_w}" ${pwdmaxlen})
	# If still needed, trunc pwd
	_w=$(_pwd_trunc "${_w}" ${pwdmaxlen})
	echo "${_w}"
}

###
# Function section with functions that get executed each time the prompt gets show
###

pp_corrected_load()
{
	local load
	if [ -r /proc/loadavg ] ; then
		load=$(cat /proc/loadavg | cut -d \  -f 2)
	else
		local UPTIME=$(uptime 2> /dev/null)
		load=${UPTIME##*:[$IFS]}
		load=${load#*, }
		load=${load%%,*}
	fi
	load=${load/./}
	load=${load#0}
	load=${load#0}
	load=$((${load:-0}/${NUMBER_OF_PROCESSORS:-1}))
	echo "${load}"
}

ppclr_load_current()
{
	# Color depends on the current system load
	local LOAD_COLOR
	local load=$(pp_corrected_load)
	if [ ${load:-0} -ge 500 ]; then
		LOAD_COLOR=${PPCLR_LOAD_CRITICAL}
	elif [ ${load:-0} -ge 100 ]; then
		LOAD_COLOR=${PPCLR_LOAD_HIGH}
	elif [ ${load:-0} -ge 70 ]; then
		LOAD_COLOR=${PPCLR_LOAD_MEDIUM}
	else
		LOAD_COLOR=${PPCLR_LOAD_NORMAL}
	fi
	echo -en "${LOAD_COLOR}"
}

ppclr_wdperm_current()
{
		# Color depends on Working directory permissions (R/W or RO)
	local PERM_COLOR
	if [ -w "${PWD}" ]; then
		PERM_COLOR=${PPCLR_WDPERM_RW}
	else
		PERM_COLOR=${PPCLR_WDPERM_RO}
	fi
	echo -en "${PERM_COLOR}"
}

pp_optional_info()
{
	local optionals=''
	local screens=$(screen -ls 2> /dev/null | grep -c Detach )
	local jobs_running=$(jobs -r | wc -l )
	local jobs_stopped=$(jobs -s | wc -l )
	
	if [ ${screens} -gt 0 ]; then
		optionals="${optionals} [scr:${screens}]"
	fi
	if [[ ( ${jobs_running} -gt 0 ) || ( ${jobs_stopped} -gt 0 ) ]]; then
		optionals="${optionals} [jobs:${jobs_running}/${jobs_stopped}]"
	fi
	echo -n "${optionals}"
}

# Set Return xterm prompt string with short path (last 18 characters)
pp_termtext () 
{
	local pwdmaxlen=30
	local _w="${PWD/$HOME/~}"
	local user="${USER:-${USERNAME}}"
	local host="${HOSTNAME%%.*}"

	# If needed strip first (evt. second) dir down to one char
	_w=$(_pwd_slim "${_w}" $pwdmaxlen)
	# If still needed, trunc pwd
	_w=$(_pwd_trunc "${_w}" $pwdmaxlen)
	# We should (for now) not rely on utf-8 working in term titles
	# E.g. PuTTY shows garbage
	# Too many dots doesn't look good either, so just remove ellipsis
	_w="${_w/…/}"
	
	# Return correct escape sequences for terminal
	case "$TERM" in
	screen*)
		_screenterm_print "${user}@${host}:${_w}"
		;;
	*)
		_term_print "${user}@${host}" ICON
		_term_print "${user}@${host}:${_w}" TITLE
		;;
	esac
}

###
# Main function
###

set_bash_powerprompt()
{
	
	###
	# Internal function section with functions that get executed on login (while setting the prompt) only
	###

	ppclr_user_current()
	{
		# Color depends on user-login type
		local USER_CLR
		# Get the effective username
		local me=$(id -un)
		# Get the username according to env vars (this doesn't change to root when using su)
		local user="${USER:-${USERNAME}}"
		# Get the username we originally logged into this box with
		local realme=$(w 2> /dev/null | grep ${tty#/dev/} 2> /dev/null)
		realme=${realme%% *}
		realme=${realme:-$(id -unr)}
		if test "${UID:-$(id -u)}" = 0 ; then
			# We're running with effective root permissions
			if [ "${user}" != "${me}" ]; then
				# We've used su from a normal user account
				USER_CLR=${PPCLR_USER_ROOT_SU}
			else
				# We've become root in another way
				if [[ ${SUDO_USER} ]]; then
					# We've used sudo bash or something similar; unwanted
					USER_CLR=${PPCLR_USER_ROOT_SUDO}
				else
					if [ "${user}" == "${realme}" ]; then
						# We're logged in with root originally
						USER_CLR=${PPCLR_USER_ROOT_LOCAL}
					else
						# We've changed to a root shell
						USER_CLR=${PPCLR_USER_ROOT_LOGIN}
					fi
				fi
			fi
		else
			# We're running with normal user permissions
			if [ "${user}" == "${realme}" ]; then
				# We're still the original user
				USER_CLR=${PPCLR_USER_NORMAL}
			else
				# We changed to a different user
				USER_CLR=${PPCLR_USER_NORMAL_SU}
			fi
		fi
		echo -n "${USER_CLR}"
	}
	
	ppclr_conn_current()
	{
		# Color depends on connection type
		local CONNECTION_CLR
				
		rpid_connection_clr()
		{
			local conclr
			local parentPID
			local parent_process
			
			parentPID=${PPID};
			while [ "${parentPID}" -gt 1 ]; do
				parent_process=$(cat /proc/${parentPID}/cmdline 2> /dev/null)
				if [[ "${parent_process}" == in.*d* ]]; then
					conclr=$1
					break
				elif [[ "${parent_process}" == sshd* ]]; then
					conclr=$2
					break
				else
					conclr=$4
				fi
				parentPID=$(ps -f -p ${parentPID} | awk '{print $3}' | grep -v PPID)
			done
			if [ "${conclr}" == "" ]; then
				if [ "${TERM}" == "cygwin" ]; then
					conclr=$4
				else
					conclr=$3
				fi
			fi
			echo -n "${conclr}"
		}

		local SESS_SRC=$(expr match "$(who -m 2> /dev/null)" '.*(\(.*\))')
		if [[ ${SSH_CLIENT} ]] || [[ ${SSH2_CLIENT} ]]; then
			# We have an SSH-session
			CONNECTION_CLR=${PPCLR_CONN_SECURE}
		elif [[ -n ${SESS_SRC} ]]; then
			if [ "${SESS_SRC:0:1}" == ":" ]; then
				# We're connected from X
				CONNECTION_CLR=${PPCLR_CONN_LOCAL}
			else
				# We're remotely connected, let's find out how
				CONNECTION_CLR=$(rpid_connection_clr ${PPCLR_CONN_INSECURE} ${PPCLR_CONN_SECURE} ${PPCLR_CONN_UNKNOWN})
			fi
		elif [[ "${SESS_SRC}" == "" ]]; then
			# Seems like a local (possibly X) terminal, but we may have also been su -l'ed into a normal user,
			# while being on a remote connection! Lets check it...
			CONNECTION_CLR=$(rpid_connection_clr ${PPCLR_CONN_INSECURE} ${PPCLR_CONN_SECURE} ${PPCLR_CONN_UNKNOWN} ${PPCLR_CONN_LOCAL})
		else
			CONNECTION_CLR=${PPCLR_CONN_UNKNOWN}
		fi
		
		unset rpid_connection_clr

		echo -n "${CONNECTION_CLR}"
	}
	
	pp_prompt_sign()
	{
		# Set prompt sign depending on the user
		local prompt_sign
		case ${PP_PROMPT_CHAR} in
			bash)
				prompt_sign='\$'
				;;
			default)
				if test "${UID}" = 0 ; then
					if test "${PP_PROMPT_END}" == ''; then
						prompt_sign=" #"
					else
						prompt_sign="#"
					fi
				else
					prompt_sign=">"
				fi
				;;
			*)
				prompt_sign="${PP_PROMPT_CHAR}"
				;;
		esac
		echo -n "${prompt_sign}"
	}
	
	# Setup colordata:
	local COLOR_WHITE='\e[1;37m'
	local COLOR_LIGHTGRAY='\e[0;37m'
	local COLOR_GRAY='\e[1;30m'
	local COLOR_BLACK='\e[0;30m'
	local COLOR_RED='\e[0;31m'
	local COLOR_LIGHTRED='\e[1;31m'
	local COLOR_GREEN='\e[0;32m'
	local COLOR_LIGHTGREEN='\e[1;32m'
	local COLOR_BROWN='\e[0;33m'
	local COLOR_YELLOW='\e[1;33m'
	local COLOR_BLUE='\e[0;34m'
	local COLOR_LIGHTBLUE='\e[1;34m'
	local COLOR_PURPLE='\e[0;35m'
	local COLOR_PINK='\e[1;35m'
	local COLOR_CYAN='\e[0;36m'
	local COLOR_LIGHTCYAN='\e[1;36m'

	local COLOR_BOLD='\e[1m'
	local COLOR_DEFAULT='\e[0m'
	local COLOR_INVERSE='\e[7m'

	# Set default configuration
	# Override these in /etc/powerprompt.conf and/or ~/.powerprompt.conf and/or ~/.config/powerprompt.conf
	if [[ "${LANG#*.}" == "UTF-8" && "${TERM}" != "linux" ]];  then
		PP_PWD_ELLIPSIS='…'
	else
		PP_PWD_ELLIPSIS='..'
	fi
	local PP_PROMPT_START=''	# Can be set to '[' as some people prefer
	local PP_PROMPT_END=''		# Can be set to ']' as some people prefer
	local PP_PROMPT_SPLITTER=' '	# Can be set to ':' as some people prefer
	local PP_PROMPT_CHAR='default'	# 'default' = ">" and " #", 'bash' = bash's defaults, currently "$" and "#"
	local PP_PROMPT_PATH='default'	# 'default', 'bash', 'toplevel', 'fish', 'short', 'physical'
	local PP_GITINFO_FORMAT=" (%s)" # Can be colorized if prefered
	#  Colors:
	#  - User session type (can be local)
	local PPCLR_USER_ROOT_SUDO="${COLOR_RED}${COLOR_INVERSE}"
	local PPCLR_USER_ROOT_LOCAL="${COLOR_RED}"
	local PPCLR_USER_ROOT_LOGIN="${COLOR_LIGHTRED}"
	local PPCLR_USER_ROOT_SU="${COLOR_YELLOW}"
	local PPCLR_USER_NORMAL_SU="${COLOR_BROWN}"
	local PPCLR_USER_NORMAL="${COLOR_DEFAULT}"
	#  - Connection type (can be local)
	local PPCLR_CONN_UNKNOWN="${COLOR_RED}"
	local PPCLR_CONN_INSECURE="${COLOR_CYAN}"
	local PPCLR_CONN_SECURE="${COLOR_GREEN}"
	local PPCLR_CONN_LOCAL="${COLOR_DEFAULT}"
	# - System load (can't be local)
	PPCLR_LOAD_CRITICAL="${COLOR_RED}${COLOR_INVERSE}"
	PPCLR_LOAD_HIGH="${COLOR_RED}"
	PPCLR_LOAD_MEDIUM="${COLOR_YELLOW}"
	PPCLR_LOAD_NORMAL="${COLOR_DEFAULT}"
	# - Filepermissions in wd (can't be local)
	PPCLR_WDPERM_RW="${COLOR_DEFAULT}"
	PPCLR_WDPERM_RO="${COLOR_GRAY}"
	# - Optionals (can be local)
	local PPCLR_OPTIONALS="${COLOR_YELLOW}"
	
	local conf
	# Load any local configuration
	conf=powerprompt.conf;            test -s $conf && . $conf
	# Load systemwide configuration
	conf=/etc/powerprompt.conf;       test -s $conf && . $conf
	# Load user configuration
	conf=~/.powerprompt.conf;         test -s $conf && . $conf
	conf=~/.config/powerprompt.conf;  test -s $conf && . $conf
	unset conf
	
	# Initialize other vars
	if [ "${TERM}" != "cygwin" ]; then
		[ ${#tty} -eq 0 ] && tty=$(tty 2> /dev/null)
	else
		tty="/dev/tty"
	fi
	[ ${#NUMBER_OF_PROCESSORS} -eq 0 ] && test -r /proc/cpuinfo && NUMBER_OF_PROCESSORS=$(grep -c "model name" /proc/cpuinfo)

	# Check for title support of terminal
	test \( "${TERM}" = "xterm" -o "${TERM#screen}" != "${TERM}" \) -a -z "${EMACS}" -a -z "${MC_SID}" && USE_TERM_TITLE=1

	# Select the right pwd
	local _pwd
	case ${PP_PROMPT_PATH} in
		bash)
			_pwd="\w"
			;; # With Bash's default prompt path
		toplevel)
			_pwd="\W"
			;; # With only toplevel directory
		fish)
			_pwd="\$(fishpwd)"
			;; # With Fish's default prompt path
		short)
			_pwd="\$(spwd)"
			;; # With short path on prompt (max 2 dirs)
		physical)
			_pwd="\$(pwd -P)"
			;; # With physical path even if reached over sym link
		*)
			_pwd="\$(powerpwd)"
			;; # With Powerprompt's default prompt path
	esac
		
	# Run one-off functions that are used multiple times
	local PPCLR_USER_CURRENT=$(ppclr_user_current)                            # One-off execution (user colour)
	# Set all the parts that make up the prompt
	local _s="${PP_PROMPT_START}"
	local _u="\[${PPCLR_USER_CURRENT}\]\u\[${COLOR_DEFAULT}\]"
	local _a="\[$(ppclr_conn_current)\]@\[${COLOR_DEFAULT}\]"                 # One-off execution (connection colour)
	local _h="\[\$(ppclr_load_current)\]\h\[${COLOR_DEFAULT}\]"               # Executed every prompt (load colour)
	local _c="${PP_PROMPT_SPLITTER}"
	local _w="\[\$(ppclr_wdperm_current)\]${_pwd}\[${COLOR_DEFAULT}\]"        # Executed every prompt (pwd permission colour)
	local _e="${PP_PROMPT_END}"
	local _g="" && type -t __git_ps1 >/dev/null 2>&1 && _g="\$(__git_ps1 \"${PP_GITINFO_FORMAT:- (%s)}\")" # Executed every prompt (git details)
	local _o="\[${PPCLR_OPTIONALS}\]\$(pp_optional_info)\[${COLOR_DEFAULT}\]" # Executed every prompt (detached screens and jobs)
	local _p="\[${PPCLR_USER_CURRENT}\]$(pp_prompt_sign)\[${COLOR_DEFAULT}\]" # One-off execution (prompt sign)
	# Set Titlebar part for Terminal emulators
	local _t="" && [[ "${USE_TERM_TITLE}" == "1" ]] &&  _t="\[\$(pp_termtext)\]"  # Executed every prompt (terminal title setting escape codes)
	
	PS1="${_s}${_t}${_u}${_a}${_h}${_c}${_w}${_e}${_g}${_o}${_p} "

	# Clean up local functions
	unset pp_prompt_sign
	unset ppclr_conn_current
	unset ppclr_user_current
}

set_bash_powerprompt
unset set_bash_powerprompt
