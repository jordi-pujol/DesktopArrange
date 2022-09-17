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

_check_yn() {
	local var="${1}" \
		val="${2}"
	if [[ "${val,,}" =~ ${PATTERN_YES} ]]; then
		eval ${var}=\'y\'
	elif [[ "${val,,}" =~ ${PATTERN_NO} ]]; then
		eval ${var}=\'n\'
	else
		LogPrio="warn" _log "Variable \"${var}\" invalid value \"${val}\""
	fi
}

_check_y() {
	local var="${1}" \
		val="${2}"
	if [[ "${val,,}" =~ ${PATTERN_YES} ]]; then
		eval ${var}=\'y\'
	else
		LogPrio="warn" _log "Variable \"${var}\" invalid value \"${val}\""
	fi
}

_check_fixedsize() {
	local var="${1}" \
		val="${2}"
	if [[ "${val,,}" =~ ${PATTERN_FIXEDSIZE} ]]; then
		eval ${var}=\'${val,,}\'
	else
		LogPrio="warn" _log "Variable \"${var}\" invalid value \"${val}\""
	fi
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
	xdotool get_desktop_for_window "${windowId}"
}


GetDesktopSize() {
	awk '$2 == "*" {print $4; exit}' < <(wmctrl -d)
}

GetDesktopWorkarea() {
	awk '$2 == "*" {print $9; exit}' < <(wmctrl -d)
}

GetDesktopStatus() {
	eval $(xdotool getdisplaygeometry --shell | \
		sed -e '/^WIDTH=/s//desktopWidth=/' \
			-e '/^HEIGHT=/s//desktopHeight=/')
	desktopCurrent="$(xdotool get_desktop)"
	desktops="$(xdotool get_num_desktops)"
	#$ $ xprop -root _NET_WORKAREA
	#_NET_WORKAREA(CARDINAL) = 0, 0, 1920, 1080, 0, 0, 1920, 1080, 0, 0, 1920, 1080, 0, 0, 1920, 1080
	#$ $ xprop -root _NET_WORKAREA
	#_NET_WORKAREA(CARDINAL) = 200, 0, 1720, 1080, 200, 0, 1720, 1080, 200, 0, 1720, 1080, 200, 0, 1720, 1080
}

GetWindowGeometry() {
	eval $(xdotool getwindowgeometry --shell "${windowId}" | \
		sed -e '/^WIDTH=/s//windowWidth=/' \
			-e '/^HEIGHT=/s//windowHeight=/' \
			-e '/^X=/s//windowX=/' \
			-e '/^Y=/s//windowY=/' \
			-e '/^SCREEN=/s//windowScreen=/')
}

RuleAppend() {
	let Rules++,1
	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		[ -n "${val}" ] || \
			continue
		case "${prop}" in
		rule_check_title)
			eval rule${Rules}_check_title=\'${val}\'
		;;
		rule_check_type)
			eval rule${Rules}_check_type=\'${val}\'
		;;
		rule_check_application)
			eval rule${Rules}_check_application=\'${val}\'
		;;
		rule_check_class)
			eval rule${Rules}_check_class=\'${val}\'
		;;
		rule_check_role)
			eval rule${Rules}_check_role=\'${val}\'
		;;
		rule_check_desktop_size)
			_check_fixedsize "rule${Rules}_check_desktop_size" "${val}"
		;;
		rule_check_desktop_workarea)
			_check_fixedsize "rule${Rules}_check_desktop_workarea" "${val}"
		;;
		rule_check_delay)
			_check_natural val 0
			[ "${val}" -eq 0 ] || \
				eval rule${Rules}_check_delay=\'${val}\'
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
			_check_yn "rule${Rules}_set_minimized" "${val}"
		;;
		rule_set_maximized)
			_check_yn "rule${Rules}_set_maximized" "${val}"
		;;
		rule_set_maximized_horizontally)
			_check_yn "rule${Rules}_set_maximized_horizontally" "${val}"
		;;
		rule_set_maximized_vertically)
			_check_yn "rule${Rules}_set_maximized_vertically" "${val}"
		;;
		rule_set_fullscreen)
			_check_yn "rule${Rules}_set_fullscreen" "${val}"
		;;
		rule_set_focus)
			_check_y "rule${Rules}_set_focus" "${val}"
		;;
		rule_set_above)
			_check_yn "rule${Rules}_set_above" "${val}"
		;;
		rule_set_below)
			_check_yn "rule${Rules}_set_below" "${val}"
		;;
		rule_set_closed)
			_check_y "rule${Rules}_set_closed" "${val}"
		;;
		rule_set_killed)
			_check_y "rule${Rules}_set_killed" "${val}"
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
	done < <(set | grep -sEe "^rule_(check|set)_" | sort)
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
			rule_check_title | \
			rule_check_type | \
			rule_check_application | \
			rule_check_class | \
			rule_check_role | \
			rule_check_desktop_size | \
			rule_check_desktop_workarea)
				let rc++,1
			;;
			rule_check_delay)
				:
			;;
			*)
				LogPrio="warn" _log "Error in config: Property \"${prop}\"" \
					"has not been implemented yet"
				rc=0
				break
			;;
		esac
	done < <(set | grep -se "^rule_check_" | sort)
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
	local rule_check_title \
		rule_check_type \
		rule_check_application \
		rule_check_class \
		rule_check_role \
		rule_check_desktop_size \
		rule_check_desktop_workarea \
		rule_check_delay \
		rule_set_above \
		rule_set_below \
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
		rule_set_closed \
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
			LogPrio="err" _log "Invalid config file:" \
				"\"${HOME}/.config/${APPNAME}/config.txt\""
			exit ${ERR}
		}

	Debug="${Debug:-}"
	! printf '%s\n' "${@}" | grep -qsxiF 'debug' || \
		Debug="y"
	! printf '%s\n' "${@}" | grep -qsxiF 'xtrace' || \
		Debug="xtrace"
	if [ "${Debug}" = "xtrace" ]; then
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {bash_xtracefd}>> "${LOGFILE}.xtrace"
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
			if set | grep -se "^rule${rule}_.*=" | sort; then
				set | grep -se "^rule${rule}_check_.*=" | \
				grep -qsve "^rule${rule}_check_delay=" || \
					LogPrio="err" _log "hasn't defined any check property for rule ${rule}"
				set | cat - | grep -qse "^rule${rule}_set_.*=" || \
					LogPrio="err" _log "hasn't defined any set property for rule ${rule}"
			else
				LogPrio="err" _log "can't find any property for rule ${rule}"
			fi
		done
		echo
	fi

	_log "Configuration reloaded"
	return ${OK}
}

readonly TAB=$'\t' OK=0 ERR=1 NONE=0 \
	PATTERN_YES="^(y.*|true|on|1|enable.*)$" \
	PATTERN_NO="^(n.*|false|off|0|disable.*)$" \
	PATTERN_FIXEDSIZE="^[0-9]+x[0-9]+$"

:
