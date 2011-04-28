#!/bin/bash
# Filename:      powerprompt.sh
# Maintainer:    Jasper Boot <jasper.boot+powerprompt@gmail.com>
# Last Modified: 2011-04-28 by Jasper Boot

# Description: A powerfull prompt with the 'less is more principle' for colors
#              If nothing special is happening, prompt will be all uncolored
#
# Current Format: user@host:pwd [git section] [dynamic section]> 
# USER:
#   Red       == Root(UID 0) Login shell (i.e. sudo bash)
#   Light Red == Root(UID 0) Login shell (i.e. su -l or direct login)
#   Yellow    == Root(UID 0) privileges in non-login shell (i.e. su)
#   Brown     == SU to user other than root(UID 0)
#   Default   == Normal user
# @:
#   Red       == Insecure(?) connection (unknown type)
#   Cyan      == Insecure remote connection (eg Telnet/RSH)
#   Green     == Secure remote connection (i.e. SSH)
#   Default   == Local session
# HOST:
#   Black/Red == LoadAvg last minute >= 3
#   Red	      == LoadAvg last minute >= 2
#   Yellow    == LoadAvg last minute >= 1
#   Default   == LoadAvg last minute >= 0
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
if [[ "$-" == *i* ]]; then if [[ "${BASH##*/}" == "bash" ]]; then

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
		test -n "$_w" || _w=$PWD
		local pwdmaxlen=$2
		test -n $pwdmaxlen || pwdmaxlen=30
		if [[ "${_w:1:1}" != "~" ]]; then
			if [ ${#_w} -gt $pwdmaxlen ]; then
				_w="${_w:0:2}/${_w#/*/}";
			fi
			if [ ${#_w} -gt $pwdmaxlen ]; then
				_w="${_w:0:4}/${_w#/?/*/}";
			fi
		fi
		echo -n $_w
	}
	
	# Truncs the start of string to make it fit into a set length
	_pwd_trunc()
	{
		local _w=$1
		test -n "$_w" || _w=$PWD
		local pwdmaxlen=$2
		test -n $pwdmaxlen || pwdmaxlen=30
		if [ ${#_w} -gt $pwdmaxlen ]; then
			local pwdoffset=$(( ${#_w} - $pwdmaxlen + ${#PP_PWD_ELLIPSIS} ))
			_w="${_w:$pwdoffset:$pwdmaxlen}"
			_w="${_w#*/}"
			_w="${PP_PWD_ELLIPSIS}${_w}"
		fi
		echo -n $_w
	}
		
###
# Function section with path-truncation functions
###

	# Returns short path (last two directories; no home substitution) by openSUSE
	spwd () 
	{
		( 
			IFS=/
			set $PWD
			if test $# -le 3 ; then
				echo "$PWD"
			else
				eval echo \"${PP_PWD_ELLIPSIS}\${$(($#-1))}/\${$#}\"
			fi 
		) ;
	}
	
	# Fish's default pwd
	fishpwd()
	{
		local _w="${PWD/$HOME/~}"
		echo -n $_w | sed -e 's-/\([^/]\)\([^/]*\)-/\1-g'
		echo -n $_w | sed -n -e 's-.*/.\([^/]*\)-\1-p'
		echo
	}
	
	# Powerprompt's default pwd
	powerpwd() 
	{
		local pp_cols="$COLUMNS"
		if [[ "$pp_cols" = "" ]]; then pp_cols=80; fi
		local pwdmaxlen=$(($pp_cols/3))
		local _w="${PWD/$HOME/~}"
		# If needed strip first (evt. second) dir down to one char
		_w=$(_pwd_slim "${_w}" $pwdmaxlen)
		# If still needed, trunc pwd
		_w=$(_pwd_trunc "${_w}" $pwdmaxlen)
		echo ${_w}
	}

###
# Function section with functions that get executed each time the prompt gets show
###

	get_current_load()
	{
		local load
		if [ -r /proc/loadavg ] ; then
			load=$(cat /proc/loadavg | cut -d \  -f 1)
		else
			local UPTIME=$(uptime)
			load=${UPTIME##*:[$IFS]}
			load=${load%%,*}
		fi
		echo -n ${load/./}
	}

	ppclr_load_current()
	{
		# Color depends on the current system load
		local LOAD_COLOR
		local load=$(get_current_load)
		load=${load%.*}
		if [ ${load:-0} -ge 300 ]; then
			LOAD_COLOR=${PPCLR_LOAD_SKYHIGH}
		elif [ ${load:-0} -ge 200 ]; then
			LOAD_COLOR=${PPCLR_LOAD_HIGH}
		elif [ ${load:-0} -ge 100 ]; then
			LOAD_COLOR=${PPCLR_LOAD_MEDIUM}
		else
			LOAD_COLOR=${PPCLR_LOAD_LOW}
		fi
		echo -en $LOAD_COLOR
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
		echo -en $PERM_COLOR
	}

	pp_optional_info()
	{
		local optionals=''
		local screens=$(screen -ls 2> /dev/null | grep -c Detach )
		local jobs_running=$(jobs -r | wc -l )
		local jobs_stopped=$(jobs -s | wc -l )
		
		if [ $screens -gt 0 ]; then
			optionals="${optionals} [scr:${screens}]"
		fi
		if [[ ( $jobs_running -gt 0 ) || ( $jobs_stopped -gt 0 ) ]]; then
			optionals="${optionals} [jobs:${jobs_running}/${jobs_stopped}]"
		fi
		echo -n "$optionals"
	}

	# Set Return xterm prompt string with short path (last 18 characters)
	pp_termtext () 
	{
		local pwdmaxlen=30
		local _w="${PWD/$HOME/~}"
		local host="${HOSTNAME%%.*}"

		# If needed strip first (evt. second) dir down to one char
		_w=$(_pwd_slim "${_w}" $pwdmaxlen)
		# If still needed, trunc pwd
		_w=$(_pwd_trunc "${_w}" $pwdmaxlen)
		
		# Return correct escape sequences for terminal
		case "$TERM" in
		screen*)
			_screenterm_print "${USER}@${host}:${_w}"
			;;
		*)
			_term_print "${USER}@${host}" ICON
			_term_print "${USER}@${host}:${_w}" TITLE
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
			local me=$(whoami)
			if test "$UID" = 0 ; then
				if [ "${USER}" == "${me}" ]; then
					if [[ ${SUDO_USER} ]]; then
						USER_CLR=${PPCLR_USER_ROOT_SUDO}
					else
						USER_CLR=${PPCLR_USER_ROOT_LOGIN}
					fi
				else
					USER_CLR=${PPCLR_USER_ROOT_SU}
				fi
			else
				local realme=$(w | grep ${tty#/dev/})
				realme=${realme%% *}
				if [ "${USER}" == "${realme}" ]; then
					USER_CLR=${PPCLR_USER_NORMAL}
				else
					USER_CLR=${PPCLR_USER_NORMAL_SU}
				fi
			fi
			echo -n $USER_CLR
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
					parent_process=$(cat /proc/${parentPID}/cmdline)
					if [[ "${parent_process}" == in.*d* ]]; then
						conclr=$1
						break
					elif [[ "${parent_process}" == sshd* ]]; then
						conclr=$2
						break
					else
						conclr=$3
					fi
					parentPID=$(ps -f -p ${parentPID} | awk '{print $3}' | grep -v PPID)
				done
				echo -n $conclr
			}

			local SESS_SRC=$(who | grep "${tty#/dev/}")
			SESS_SRC=${SESS_SRC##* }
			SESS_SRC=${SESS_SRC/(/}
			SESS_SRC=${SESS_SRC/)/}
			if [[ ${SSH_CLIENT} ]] || [[ ${SSH2_CLIENT} ]]; then
				# We have a SSH-session
				CONNECTION_CLR=${PPCLR_CONN_SECURE}
			elif [[ -n ${SESS_SRC} ]]; then
				if [ "${SESS_SRC}" == "(:0.0)" ]; then
					# We're connected from X
					CONNECTION_CLR=${PPCLR_CONN_LOCAL}
				else
					# We're remotely connected, let's find out how
					CONNECTION_CLR=$(rpid_connection_clr ${PPCLR_CONN_INSECURE} ${PPCLR_CONN_SECURE} ${PPCLR_CONN_UNKNOWN})
				fi
			elif [[ "${SESS_SRC}" == "" ]]; then
				# Seems like a local terminal, but we may have also been su -l'ed into a normal user,
				# while being on a remote connection! Lets check it...
				CONNECTION_CLR=$(rpid_connection_clr ${PPCLR_CONN_INSECURE} ${PPCLR_CONN_SECURE} ${PPCLR_CONN_LOCAL})
			else
				CONNECTION_CLR=${PPCLR_CONN_UNKNOWN}
			fi
			
			echo -n $CONNECTION_CLR
		}
		
		pp_prompt_sign()
		{
			# Set prompt sign depending on the user
			local prompt_sign
			case $PP_PROMPT_CHAR in
				bash)
					prompt_sign='\$'
					;;
				*)
					if test "$UID" = 0 ; then
						prompt_sign=" #"
					else
						prompt_sign=">"
					fi
					;;
			esac
			echo -n "$prompt_sign"
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
		# Override these in /etc/powerprompt.conf and/or ~/.powerprompt.conf
		PP_PWD_ELLIPSIS='..'
		local PP_PROMPT_START=''	# Can be set to '[' as some people prefer
		local PP_PROMPT_END=''		# Can be set to ']' as some people prefer
		local PP_PROMPT_SPLITTER=':'	# Can be set to ' ' as some people prefer
		local PP_PROMPT_CHAR='default'	# 'default' = ">" and " #", 'bash' = bash's defaults, currently "$" and "#"
		local PP_PROMPT_PATH='default'	# 'default', 'bash', 'toplevel', 'fish', 'short', 'physical'
		local PP_GITINFO_FORMAT=" (\[${COLOR_DEFAULT}\]%s\[${COLOR_DEFAULT}\])"
		#  Colors:
		#  - User session type (can be local)
		local PPCLR_USER_ROOT_SUDO="${COLOR_RED}"
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
		PPCLR_LOAD_SKYHIGH="${COLOR_RED}${COLOR_INVERSE}"
		PPCLR_LOAD_HIGH="${COLOR_RED}"
		PPCLR_LOAD_MEDIUM="${COLOR_YELLOW}"
		PPCLR_LOAD_LOW="${COLOR_DEFAULT}"
		# - Filepermissions in wd (can't be local)
		PPCLR_WDPERM_RW="${COLOR_DEFAULT}"
		PPCLR_WDPERM_RO="${COLOR_GRAY}"
		# - Optionals (can be local)
		local PPCLR_OPTIONALS="${COLOR_YELLOW}"
		
		# Load systemwide configuration
		test -s /etc/powerprompt.conf && . /etc/powerprompt.conf
		# Load user configuration
		test -s ~/.powerprompt.conf && . ~/.powerprompt.conf
		
		# Initialize other vars
		if [ ${#tty} -eq 0 ]; then tty=$(tty); fi
		
		# Run the one-time functions
		local PPCLR_USER_CURRENT=$(ppclr_user_current)
		local PPCLR_CONN_CURRENT=$(ppclr_conn_current)
		local PP_PROMPT_SIGN=$(pp_prompt_sign)
		# Check for title support of terminal
		test \( "$TERM" = "xterm" -o "${TERM#screen}" != "$TERM" \) -a -z "$EMACS" -a -z "$MC_SID" && USE_TERM_TITLE=1

		local _s="${PP_PROMPT_START}"
		local _u="\[${PPCLR_USER_CURRENT}\]\u\[${COLOR_DEFAULT}\]"
		local _a="\[${PPCLR_CONN_CURRENT}\]@\[${COLOR_DEFAULT}\]"
		local _h="\[\$(ppclr_load_current)\]\h\[${COLOR_DEFAULT}\]"
		local _c="${PP_PROMPT_SPLITTER}"

		local _w
		case $PP_PROMPT_PATH in
			bash)
				# With Bash's default prompt path
				_w="\[\$(ppclr_wdperm_current)\]\w\[${COLOR_DEFAULT}\]"
				;;
			toplevel)
				# With only toplevel directory
				_w="\[\$(ppclr_wdperm_current)\]\W\[${COLOR_DEFAULT}\]"
				;;
			fish)
				# With Fish's default prompt path
				_w="\[\$(ppclr_wdperm_current)\]\$(fishpwd)\[${COLOR_DEFAULT}\]"
				;;
			short)
				# With short path on prompt (max 2 dirs)
				_w="\[\$(ppclr_wdperm_current)\]\$(spwd)\[${COLOR_DEFAULT}\]"
				;;
			physical)
				# With physical path even if reached over sym link
				_w="\[\$(ppclr_wdperm_current)\]\$(pwd -P)\[${COLOR_DEFAULT}\]"
				;;
			*)
				# With Powerprompt's default prompt path
				_w="\[\$(ppclr_wdperm_current)\]\$(powerpwd)\[${COLOR_DEFAULT}\]"
				;;
		esac
			
		local _g
		type -t __git_ps1 >/dev/null 2>&1;
		if [ $? -eq 0 ]; then
			_g="\$(__git_ps1 \"${PP_GITINFO_FORMAT:- (%s)}\")"
		else
			_g=""
		fi
		
		local _e="${PP_PROMPT_END}"
		local _o="\[${PPCLR_OPTIONALS}\]\$(pp_optional_info)\[${COLOR_DEFAULT}\]"
		local _p="\[${PPCLR_USER_CURRENT}\]${PP_PROMPT_SIGN}\[${COLOR_DEFAULT}\]"

		# Set Titlebar for Terminal emulators
		if [[ "$USE_TERM_TITLE" == 1 ]]; then
			local _t="\[\$(pp_termtext)\]"
		fi
		
		PS1="${_s}${_t}${_u}${_a}${_h}${_c}${_w}${_g}${_e}${_o}${_p} "
	}

	set_bash_powerprompt
	unset set_bash_powerprompt
fi; fi
