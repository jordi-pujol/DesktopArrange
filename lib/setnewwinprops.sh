#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.2 $
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

GetWindowTitle() {
	local windowId="${1}" name
	name="$(xdotool getwindowname "${windowId}")"
	[ -n "${name}" ] && \
		printf '%s\n' "${name}" || \
		return ${ERR}
}

GetWindowType() {
	local windowId="${1}"
	xprop -id "${windowId}" _NET_WM_WINDOW_TYPE | \
		sed -nre '\|.*[=] (.*)$|!{q1};s//\1/p'
}

GetWindowApplication() {
	local windowId="${1}"
	2> /dev/null ps -ho cmd "$(xdotool getwindowpid "${windowId}")" || \
		return ${ERR}
}

GetWindowClass() {
	local windowId="${1}"
	xprop -id "${windowId}" WM_CLASS | \
		sed -nre '\|.*[=] (.*)$|!{q1};s//\1/p'
}

GetWindowRole() {
	local windowId="${1}"
	xprop -id "${windowId}" WM_WINDOW_ROLE | \
		sed -nre '\|.*[=] "(.*)"$| s//\1/p'
}

GetWindowIsMaximized() {
	local windowId="${1}"
	xprop -id "${windowId}" _NET_WM_STATE | \
		sed -nre '\|.*[=] "(.*)"$| s//\1/p' | \
		grep -swF '_NET_WM_STATE_MAXIMIZED_HORZ' | \
		grep -swF '_NET_WM_STATE_MAXIMIZED_VERT' || :
}

GetWindowIsMaximizedHorz() {
	local windowId="${1}"
	xprop -id "${windowId}" _NET_WM_STATE | \
		sed -nre '\|.*[=] "(.*)"$| s//\1/p' | \
		grep -swF '_NET_WM_STATE_MAXIMIZED_HORZ' || :
}

GetWindowIsMaximizedVert() {
	local windowId="${1}"
	xprop -id "${windowId}" _NET_WM_STATE | \
		sed -nre '\|.*[=] "(.*)"$| s//\1/p' | \
		grep -swF '_NET_WM_STATE_MAXIMIZED_VERT' || :
}

GetWindowDesktop() {
	local windowId="${1}"
	get_desktop_for_window "${windowId}"
}


GetDesktopSize() {
	awk '$2 == "*" {print $4; exit}' < <(wmctrl -d)
}

GetDesktopWorkarea() {
	awk '$2 == "*" {print $9; exit}' < <(wmctrl -d)
}

GetDesktopStatus() {
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

GetWindowGeometry() {
	local WIDTH HEIGHT X Y SCREEN
	eval $(xdotool getwindowgeometry --shell "${windowId}")
	windowWidth="${WIDTH}"
	windowHeight="${HEIGHT}"
	windowX="${X}"
	windowY="${Y}"
	windowDesktop="${SCREEN}"
}

RuleAppend() {
	let Rules++,1
	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		[ -n "${val}" ] || \
			continue
		case "${prop}" in
		rule_met_title)
			eval rule${Rules}_met_title=\'${val}\'
		;;
		rule_met_type)
			eval rule${Rules}_met_type=\'${val}\'
		;;
		rule_met_application)
			eval rule${Rules}_met_application=\'${val}\'
		;;
		rule_met_class)
			eval rule${Rules}_met_class=\'${val}\'
		;;
		rule_met_role)
			eval rule${Rules}_met_role=\'${val}\'
		;;
		rule_met_desktop_size)
			eval rule${Rules}_met_desktop_size=\'${val,,}\'
		;;
		rule_met_desktop_workarea)
			eval rule${Rules}_met_desktop_workarea=\'${val,,}\'
		;;
		rule_met_delay)
			_check_natural val 0
			[ "${val}" -eq 0 ] || \
				eval rule${Rules}_met_delay=\'${val}\'
		;;
		rule_set_position)
			val="$(tr -s ' ,' ' ' <<< "${val,,}")"
			if [ "$(wc -w <<< "${val}")" != 2 ]; then
				_log "Property \"${prop}\" invalid value \"${val}\""
			else
				_check_integer_pair val x y
				eval rule${Rules}_set_position=\'${val}\'
			fi
		;;
		rule_set_size)
			val="$(tr -s ' ,' ' ' <<< "${val,,}")"
			if [ "$(wc -w <<< "${val}")" != 2 ]; then
				_log "Property \"${prop}\" invalid value \"${val}\""
			else
				_check_integer_pair val x y
				eval rule${Rules}_set_size=\'${val}\'
			fi
		;;
		rule_set_minimized)
			eval rule${Rules}_set_minimized=\'${val,,}\'
		;;
		rule_set_maximized)
			eval rule${Rules}_set_maximized=\'${val,,}\'
		;;
		rule_set_maximized_horizontally)
			eval rule${Rules}_set_maximized_horizontally=\'${val,,}\'
		;;
		rule_set_maximized_vertically)
			eval rule${Rules}_set_maximized_vertically=\'${val,,}\'
		;;
		rule_set_fullscreen)
			eval rule${Rules}_set_fullscreen=\'${val,,}\'
		;;
		rule_set_focus)
			eval rule${Rules}_set_focus=\'${val,,}\'
		;;
		rule_set_above)
			eval rule${Rules}_set_above=\'${val,,}\'
		;;
		rule_set_killed)
			eval rule${Rules}_set_killed=\'${val,,}\'
		;;
		rule_set_desktop)
			_check_natural val 0
			eval rule${Rules}_set_desktop=\'${val}\'
		;;
		rule_set_active_desktop)
			_check_natural val 0
			eval rule${Rules}_set_active_desktop=\'${val}\'
		;;
		*)
			_log "Property \"${prop}\" is not implemented yet"
		# 	_check_yn_val "rule_set_pin" ""
		# 	_check_yn_val "rule_set_bottom" ""
		# 	_check_ind_val "rule_set_decoration" ""
		# 	_check_int_pair_val "rule_set_pointer" ""
				;;
		esac
	done < <(set | grep -se "^rule_[ms]et_" | sort)
	# 
	# 	if [ -n "${Debug}" ]; then
	# 		local msg="Adding new rule $( \
	# 			WindowName "${Rules}" \
	# 			"${rule_bssid:-"${BEL}"}" \
	# 			"${rule_ssid:-"${BEL}"}")"
	# 		_log "${msg}"
	# 	fi
}

AddRule() {
	local prop val rc=0
	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		[ -n "${val}" ] || \
			continue
		case "${prop}" in
			rule_met_title | \
			rule_met_type | \
			rule_met_application | \
			rule_met_class | \
			rule_met_role | \
			rule_met_desktop_size | \
			rule_met_desktop_workarea)
				let rc++,1
			;;
			rule_met_delay)
				:
			;;
			*)
				LogPrio="warn" _log "Error in config: Property \"${prop}\"" \
					"has not been implemented yet"
				rc=0
				break
			;;
		esac
	done < <(set | grep -se "^rule_met_" | sort)
	if [ ${rc} -eq 0 ]; then
		LogPrio="warn" _log "Error in config. Can't add a new rule"
	else
		RuleAppend
	fi
	unset $(set | awk -F '=' \
		'$1 ~ "^rule_" {print $1}') 2> /dev/null || :
	return ${OK}
}

LoadConfig() {
	local rule_met_title \
		rule_met_type \
		rule_met_application \
		rule_met_class \
		rule_met_role \
		rule_met_desktop_size \
		rule_met_desktop_workarea \
		rule_met_delay \
		rule_set_above \
		rule_set_maximized \
		rule_set_maximized_horizontally \
		rule_set_maximized_vertically \
		rule_set_fullscreen \
		rule_set_focus \
		rule_set_minimized \
		rule_set_pin \
		rule_set_position \
		rule_set_size \
		rule_set_active_desktop \
		rule_set_desktop \
		rule_set_decoration \
		rule_set_killed \
		rule_set_pointer \
		bash_xtracefd \
		rule msg="Loading configuration"

	# config variables, default values
	Debug=""
	unset $(set | awk -F '=' \
		'$1 ~ "^rule[[:digit:]]*_" {print $1}') 2> /dev/null || :

	_log "${msg}"

	Rules=${NONE}
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

	if [ ${Rules} -eq ${NONE} ]; then
		LogPrio="warn" _log "Have not configured any rule"
	else
		rule=${NONE}
		while [ $((rule++)) -lt ${Rules} ]; do
			echo
			set | grep -se "^rule${rule}_.*=" | sort
		done
		echo
	fi

	msg="Configuration reloaded"
	_log "${msg}"
	return ${OK}
}

:
