#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for selected opening windows
#
#  $Revision: 0.1 $
#
#  Copyright (C) 2022-2022 Jordi Pujol <jordipujolp AT gmail DOT com>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3, or (at your option)
#  any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#************************************************************************

. /usr/lib/setnewwinprops/setnewwinprops
_unquote() {
	printf '%s\n' "${@}" | \
		sed -re "s/^([\"](.*)[\"]|['](.*)['])$/\2\3/"
}

_datetime() {
	date +'%F %X'
}

_ps_children() {
	local ppid=${1:-${$}} \
		excl="${2:-"0"}" \
		pid
	for pid in $(pgrep -P ${ppid} | \
	grep -svwEe "${excl}"); do
		_ps_children ${pid} "${excl}"
		pidsChildren="${pidsChildren}${pid}${TAB}"
	done
}

_check_integer() {
	local n="${1}" \
		d="${2}" \
		v="" w rc=${OK}
	eval w=\"\${${n}:-}\"
	let "v=${w}" 2> /dev/null || \
		rc=${?}
	if [ ${rc} -gt 1 ] || [ -z "${v}" ]; then
		_log "Config error:" \
			"Invalid integer value \"${w}\" for \"${n}\"," \
			"assuming default \"${d}\""
		v="${d}"
	fi
	if [ "${v}" = "${v//^[[:digit:]-]/}" ]; then
		let "${n}=${v},1"
	else
		eval "${n}=\"${v}\""
	fi
	return ${OK}
}

_check_integer_pair() {
	local n="${1}" \
		d1="${2}" \
		d2="${3}" \
		v="" w x y rc=${OK}
	eval w=\"\${${n}:-}\"
	x="$(cut -f 1 -s -d ' ' <<< "${w}")"
	if [ "${x}" = "${x//[^[:digit:]-]/}" ]; then
		_check_integer x "${d1}"
	fi
	y="$(cut -f 2 -s -d ' ' <<< "${w}")"
	if [ "${y}" = "${y//[^[:digit:]-]/}" ]; then
		_check_integer y "${d2}"
	fi
	eval "${n}=\"${x} ${y}\""
	return ${OK}
}

_check_natural() {
	local n="${1}" \
		d="${2}" \
		v="" w rc=${OK}
	eval w=\"\${${n}:-}\"
	let "v=${w}" 2> /dev/null || \
		rc=${?}
	if [ ${rc} -gt 1 ] || [ -z "${v}" ] || [ "${v}" -lt 0 ]; then
		_log "Config error:" \
			"Invalid integer value \"${w}\" for \"${n}\"," \
			"assuming default \"${d}\""
		v="${d}"
	fi
	let "${n}=${v},1"
	return ${OK}
}

# priority: info notice warn err debug
_log() {
	local msg="${@}" \
		p="daemon.${LogPrio:-"notice"}"
	LogPrio=""
	printf '%s\n' "$(_datetime) ${p}: ${@}" >> "${LOGFILE}"
	return ${OK}
}

GetTitle() {
	local id="${1}"
	xprop -id "${id}" _NET_WM_NAME | \
		sed -re '\|.*[=] "(.*)"$| s//\1/'
	# xdotool getwindowname "${id}"
}

GetType() {
	local id="${1}"
	xprop -id "${id}" _NET_WM_WINDOW_TYPE | \
		awk '{print $NF}'
}

GetApplication() {
	local id="${1}" pid
	pid="$(xprop -id "${id}" _NET_WM_PID | \
		awk '{print $NF}')"
	ps -ho cmd "${pid}"
	# xdotool getwindowpid "${id}"
}

GetClass() {
	local id="${1}"
	xprop -id "${id}" WM_CLASS | \
		sed -re '\|.*[=] (.*)$| s//\1/'
}

GetRole() {
	local id="${1}"
	xprop -id "${id}" WM_WINDOW_ROLE | \
		sed -re '\|.*[=] "(.*)"$| s//\1/' | \
		grep -svF "WM_WINDOW_ROLE:  not found." || :
	# $ xprop -id 0x2200003 | grep -i role
	# WM_WINDOW_ROLE(STRING) = "xfce4-terminal-1663170190-2467579532"
}

WindowAppend() {
	let Windows++,1
	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		[ -n "${val}" ] || \
			continue
		case "${prop}" in
		window_get_title)
			eval window${Windows}_get_title=\'${val}\'
		;;
		window_get_type)
			eval window${Windows}_get_type=\'${val}\'
		;;
		window_get_application)
			eval window${Windows}_get_application=\'${val}\'
		;;
		window_get_class)
			eval window${Windows}_get_class=\'${val}\'
		;;
		window_get_role)
			eval window${Windows}_get_role=\'${val}\'
		;;
		window_get_delay)
			_check_natural val 0
			[ "${val}" -eq 0 ] || \
				eval window${Windows}_get_delay=\'${val}\'
		;;
		window_set_position)
			val="$(tr -s ' ,' ' ' <<< "${val,,}")"
			if [ "$(wc -w <<< "${val}")" != 2 ]; then
				_log "Property \"${prop}\" invalid value \"${val}\""
			else
				_check_integer_pair val x y
				eval window${Windows}_set_position=\'${val}\'
			fi
		;;
		window_set_size)
			val="$(tr -s ' ,' ' ' <<< "${val,,}")"
			if [ "$(wc -w <<< "${val}")" != 2 ]; then
				_log "Property \"${prop}\" invalid value \"${val}\""
			else
				_check_integer_pair val x y
				eval window${Windows}_set_size=\'${val}\'
			fi
		;;
		window_set_minimized)
			eval window${Windows}_set_minimized=\'${val,,}\'
		;;
		window_set_maximized)
			eval window${Windows}_set_maximized=\'${val,,}\'
		;;
		window_set_maximized_horizontally)
			eval window${Windows}_set_maximized_horizontally=\'${val,,}\'
		;;
		window_set_maximized_vertically)
			eval window${Windows}_set_maximized_vertically=\'${val,,}\'
		;;
		window_set_fullscreen)
			eval window${Windows}_set_fullscreen=\'${val,,}\'
		;;
		window_set_focus)
			eval window${Windows}_set_focus=\'${val,,}\'
		;;
		window_set_above)
			eval window${Windows}_set_above=\'${val,,}\'
		;;
		window_set_killed)
			eval window${Windows}_set_killed=\'${val,,}\'
		;;
		window_set_desktop)
			_check_natural val 0
			eval window${Windows}_set_desktop=\'${val}\'
		;;
		window_set_active_desktop)
			_check_natural val 0
			eval window${Windows}_set_active_desktop=\'${val}\'
		;;
		*)
			_log "Property \"${prop}\" is not implemented yet"
		# 	_check_yn_val "window_set_pin" ""
		# 	_check_yn_val "window_set_bottom" ""
		# 	_check_ind_val "window_set_decoration" ""
		# 	_check_int_pair_val "window_set_pointer" ""
				;;
		esac
	done < <(set | grep -se "^window_[gs]et_" | sort)
	# 
	# 	if [ -n "${Debug}" ]; then
	# 		local msg="Adding new window $( \
	# 			WindowName "${Windows}" \
	# 			"${window_bssid:-"${BEL}"}" \
	# 			"${window_ssid:-"${BEL}"}")"
	# 		_log "${msg}"
	# 	fi
}

AddWindow() {
	local prop val rc=0
	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		[ -n "${val}" ] || \
			continue
		case "${prop}" in
			window_get_title | \
			window_get_type | \
			window_get_application | \
			window_get_class | \
			window_get_role)
				let rc++,1
			;;
			window_get_delay)
				:
			;;
			*)
				rc=0
				break
			;;
		esac
	done < <(set | grep -se "^window_get_" | sort)
	if [ ${rc} -eq 0 ]; then
		_log "Error in config. Can't add a new window"
	else
		WindowAppend
	fi
	unset $(set | awk -F '=' \
		'$1 ~ "^window_" {print $1}') 2> /dev/null || :
	return ${OK}
}

LoadConfig() {
	local window_get_title \
		window_get_type \
		window_get_application \
		window_get_class \
		window_get_role \
		window_set_above \
		window_set_maximized \
		window_set_maximized_horizontally \
		window_set_maximized_vertically \
		window_set_fullscreen \
		window_set_focus \
		window_set_minimized \
		window_set_pin \
		window_set_position \
		window_set_size \
		window_set_active_desktop \
		window_set_desktop \
		window_set_decoration \
		window_set_killed \
		window_set_pointer \
		bash_xtracefd \
		window msg="Loading configuration"

	# config variables, default values
	Debug=""
	unset $(set | awk -F '=' \
		'$1 ~ "^window[[:digit:]]*_" {print $1}') 2> /dev/null || :

	_log "${msg}"

	Windows=${NONE}
	[ -s "${HOME}/.config/${APPNAME}/config.txt" ] && \
		. "${HOME}/.config/${APPNAME}/config.txt" || {
			LogPrio="err" _log "Invalid config file."
			exit ${ERR}
		}

	Debug="${Debug:-}"
	! printf '%s\n' "${@}" | grep -qsxiF 'debug' || \
		Debug="y"
	! printf '%s\n' "${@}" | grep -qsxiF 'xtrace' || \
		Debug="xtrace"
	if [ "${Debug}" = "xtrace" ]; then
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {bash_xtracefd}> "${LOGFILE}.xtrace"
		BASH_XTRACEFD=${bash_xtracefd}
		set -o xtrace
	else
		set +o xtrace
	fi

	LogPrio="info" _log "${msg}"

	if [ -n "${Debug}" -o ${#} -gt ${NONE} ]; then
		msg="daemon's command line"
		[ ${#} -gt ${NONE} ] && \
			msg="${msg} options:$(printf ' "%s"' "${@}")" || \
			msg="${msg} is empty"
		_log "${msg}"
	fi

	if [ ${Windows} -eq ${NONE} ]; then
		LogPrio="warn" _log "Have not configured any window"
	else
		local window=${NONE}
		while [ $((window++)) -lt ${Windows} ]; do
			echo
			set | grep -se "^window${window}_.*=" | sort
		done
		echo
	fi

	msg="Configuration reloaded"
	_log "${msg}"
	return ${OK}
}

DesktopStatus() {
	local WIDTH HEIGHT
	eval $(xdotool getdisplaygeometry --shell)
	desktopWidth="${WIDTH}"
	desktopHeight="${HEIGHT}"
	desktopCurrent="$(xdotool get_desktop)"
	desktops="$(xdotool get_num_desktops)"
	#$ $ xprop -root _NET_WORKAREA
	#_NET_WORKAREA(CARDINAL) = 0, 0, 1920, 1080, 0, 0, 1920, 1080, 0, 0, 1920, 1080, 0, 0, 1920, 1080
	#$ $ xprop -root _NET_WORKAREA
	#_NET_WORKAREA(CARDINAL) = 200, 0, 1720, 1080, 200, 0, 1720, 1080, 200, 0, 1720, 1080, 200, 0, 1720, 1080
}

WindowStatus() {
	local WIDTH HEIGHT X Y SCREEN
	eval $(xdotool getwindowgeometry --shell "${id}")
	windowWidth="${WIDTH}"
	windowHeight="${HEIGHT}"
	windowX="${X}"
	windowY="${Y}"
	windowDesktop="${SCREEN}"
}
