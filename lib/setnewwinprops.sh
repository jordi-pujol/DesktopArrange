#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.10 $
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

# priority: info notice warn err debug
_log() {
	local msg \
		p="${LogPrio:-"notice"}"
	LogPrio=""
	msg="$(_datetime) ${p}: ${@}"
	printf '%s\n' "${msg}" >> "${LOGFILE}"
	return ${OK}
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
		eval ${var}=\'${AFFIRMATIVE}\'
	elif [[ "${val,,}" =~ ${PATTERN_NO} ]]; then
		eval ${var}=\'${NEGATIVE}\'
	else
		LogPrio="warn" _log "Variable \"${var}\" invalid value \"${val}\""
	fi
}

_check_y() {
	local var="${1}" \
		val="${2}"
	if [[ "${val,,}" =~ ${PATTERN_YES} ]]; then
		eval ${var}=\'${AFFIRMATIVE}\'
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

GetXroot() {
	local XROOT t=0
	while ! XROOT="$(xprop -root _NET_SUPPORTING_WM_CHECK | \
	awk '$NF ~ "^0x[0-9A-Fa-f]+$" {print $NF; rc=-1; exit}
	END{exit rc+1}')" && \
	[ $((t++)) -lt 5 ]; do
		sleep 1
	done 2> /dev/null
	[ -n "${XROOT}" ] && \
		echo "${XROOT}" || \
		return ${ERR}
}

AlreadyRunning() {
	[ -e "${PIDFILE}" ] && \
	kill -s 0 "$(cat "${PIDFILE}")" 2> /dev/null || \
		return ${ERR}
	echo "Info: ${APPNAME} is running in pid $(cat "${PIDFILE}")" >&2
	cat "${PIDFILE}"
}

GetWindowProp() {
	xprop -len 1024 -id "${@}"
}

GetWindowPropAtom() {
	local windowId="${1}" \
		atom="${2}"
	sed -nre '\|.*[=] (.*)$|!{q1};s//\1/p' \
		< <(GetWindowProp ${windowId} "${atom}")
}

GetWindowState() {
	local windowId="${1}"
	awk '$0 ~ "window state:" {print $NF}' \
		< <(GetWindowProp ${windowId} "WM_STATE")
}

GetWindowWMState() {
	local windowId="${1}"
	GetWindowPropAtom ${windowId} "_NET_WM_STATE"
}

IsWindowWMStateActive() {
	local windowId="${1}" wmstate
	wmstate="$(GetWindowWMState "${windowId}")" || \
		return ${ERR}
	shift
	[ $(grep -s --count -wF "$(printf '%s\n' "${@}")" \
	< <(printf '%s\n' ${wmstate})) -eq ${#} ]
}

GetWindowTitle() {
	local windowId="${1}" name
	name="$(xdotool getwindowname "${windowId}")"
	[ -n "${name}" ] && \
		printf '%s\n' "${name}" || \
		return ${ERR}
}

GetWindowAppName() {
	local windowId="${1}"
	_unquote "$(GetWindowPropAtom ${windowId} "_OB_APP_NAME")"
}

GetWindowType() {
	local windowId="${1}"
	GetWindowPropAtom ${windowId} "_NET_WM_WINDOW_TYPE"
}

GetWindowApplication() {
	local windowId="${1}"
	ps -ho cmd "$(xdotool getwindowpid "${windowId}")" || \
		return ${ERR}
}

GetWindowClass() {
	local windowId="${1}"
	GetWindowPropAtom ${windowId} "WM_CLASS"
}

GetWindowRole() {
	local windowId="${1}"
	GetWindowPropAtom ${windowId} "WM_WINDOW_ROLE"
}

GetWindowIsMaximized() {
	local windowId="${1}"
	IsWindowWMStateActive ${windowId} \
	'_NET_WM_STATE_MAXIMIZED_HORZ' \
	'_NET_WM_STATE_MAXIMIZED_VERT' && \
		echo "${AFFIRMATIVE}" || \
		echo "${NEGATIVE}"
}

GetWindowIsMaximizedHorz() {
	local windowId="${1}"
	IsWindowWMStateActive ${windowId} \
	'_NET_WM_STATE_MAXIMIZED_HORZ' && \
		echo "${AFFIRMATIVE}" || \
		echo "${NEGATIVE}"
}

GetWindowIsMaximizedVert() {
	local windowId="${1}"
	IsWindowWMStateActive ${windowId} \
	'_NET_WM_STATE_MAXIMIZED_VERT' && \
		echo "${AFFIRMATIVE}" || \
		echo "${NEGATIVE}"
}

GetWindowIsShaded() {
	local windowId="${1}"
	IsWindowWMStateActive ${windowId} \
	'_NET_WM_STATE_SHADED' && \
		echo "${AFFIRMATIVE}" || \
		echo "${NEGATIVE}"
}

GetWindowIsSticky() {
	local windowId="${1}"
	IsWindowWMStateActive ${windowId} \
	'_NET_WM_STATE_STICKY' && \
		echo "${AFFIRMATIVE}" || \
		echo "${NEGATIVE}"
}

GetWindowDesktop() {
	local windowId="${1}"
	xdotool get_desktop_for_window ${windowId} 2> /dev/null || :
}

WindowExists() {
	local windowId="$(printf '0x%0x' "${1}")"
	grep -qswF "${windowId}" < <(tr -s ' ,' ' ' \
		< <(cut -f 2- -s -d '#' \
		< <(xprop -root "_NET_CLIENT_LIST")))
}

GetDesktopSize() {
	awk '$2 == "*" {print $4; exit}' < <(wmctrl -d)
}

GetDesktopWorkarea() {
	awk '$2 == "*" {print $9; exit}' < <(wmctrl -d)
}

GetDesktopStatus() {
	eval $(sed -e '/^WIDTH=/s//desktopWidth=/' \
			-e '/^HEIGHT=/s//desktopHeight=/' \
			< <(xdotool getdisplaygeometry --shell))
	desktopCurrent="$(xdotool get_desktop)"
	desktops="$(xdotool get_num_desktops)"
}

GetWindowGeometry() {
	eval $(sed -e '/^WIDTH=/s//windowWidth=/' \
			-e '/^HEIGHT=/s//windowHeight=/' \
			-e '/^X=/s//windowX=/' \
			-e '/^Y=/s//windowY=/' \
			-e '/^SCREEN=/s//windowScreen=/' \
			< <(xdotool getwindowgeometry --shell "${windowId}"))
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
		rule_check_state)
			eval rule${Rules}_check_state=\'${val}\'
			;;
		rule_check_type)
			eval rule${Rules}_check_type=\'${val}\'
			;;
		rule_check_app_name)
			eval rule${Rules}_check_app_name=\'${val}\'
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
		rule_check_desktop)
			_check_natural val ${NONE}
			eval rule${Rules}_check_desktop=\'${val}\'
			;;
		rule_check_is_maximized)
			_check_yn "rule${Rules}_check_is_maximized" "${val}"
			;;
		rule_check_is_maximized_horz)
			_check_yn "rule${Rules}_check_is_maximized_horz" "${val}"
			;;
		rule_check_is_maximized_vert)
			_check_yn "rule${Rules}_check_is_maximized_vert" "${val}"
			;;
		rule_check_is_shaded)
			_check_yn "rule${Rules}_check_is_shaded" "${val}"
			;;
		rule_check_is_sticky)
			_check_yn "rule${Rules}_check_is_sticky" "${val}"
			;;
		rule_check_desktop_size)
			_check_fixedsize "rule${Rules}_check_desktop_size" "${val}"
			;;
		rule_check_desktop_workarea)
			_check_fixedsize "rule${Rules}_check_desktop_workarea" "${val}"
			;;
		rule_set_delay)
			_check_natural val ${NONE}
			[ "${val}" -eq ${NONE} ] || \
				eval rule${Rules}_set_delay=\'${val}\'
			;;
		rule_set_position)
			val="$(tr -s ' ,' ' ' <<< "${val,,}")"
			if [ "$(wc -w <<< "${val}")" != 2 ]; then
				_log "Property \"${prop}\" invalid value \"${val}\""
			else
				_check_integer_pair val "x" "y"
				eval rule${Rules}_set_position=\'${val}\'
			fi
			;;
		rule_set_size)
			val="$(tr -s ' ,' ' ' <<< "${val,,}")"
			if [ "$(wc -w <<< "${val}")" != 2 ]; then
				_log "Property \"${prop}\" invalid value \"${val}\""
			else
				_check_integer_pair val "x" "y"
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
		rule_set_shaded)
			_check_yn "rule${Rules}_set_shaded" "${val}"
			;;
		rule_set_sticky)
			_check_yn "rule${Rules}_set_sticky" "${val}"
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
			_check_natural val ${NONE}
			eval rule${Rules}_set_desktop=\'${val}\'
			;;
		rule_set_active_desktop)
			_check_natural val ${NONE}
			eval rule${Rules}_set_active_desktop=\'${val}\'
			;;
		*)
			_log "Property \"${prop}\" is not implemented yet"
			;;
		esac
	done < <(sort \
	< <(grep -sEe "^rule_(check|set)_" \
	< <(set)))
}

AddRule() {
	local prop val rc=${NONE}
	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		[ -n "${val}" ] || \
			continue
		case "${prop}" in
			rule_check_title | \
			rule_check_state | \
			rule_check_type | \
			rule_check_app_name | \
			rule_check_application | \
			rule_check_class | \
			rule_check_role | \
			rule_check_desktop | \
			rule_check_desktop_size | \
			rule_check_desktop_workarea | \
			rule_check_is_maximized | \
			rule_check_is_maximized_horz | \
			rule_check_is_maximized_vert | \
			rule_check_is_shaded | \
			rule_check_is_sticky)
				let rc++,1
			;;
			*)
				LogPrio="warn" _log "Error in config: Property \"${prop}\"" \
					"has not been implemented yet"
				rc=${NONE}
				break
			;;
		esac
	done < <(sort \
	< <(grep -se "^rule_check_" \
	< <(set)))
	if [ ${rc} -eq ${NONE} ]; then
		LogPrio="warn" _log "Error in config. Can't add a new rule"
	else
		RuleAppend
	fi
	unset $(awk -F '=' \
		'$1 ~ "^rule_" {print $1}' \
		< <(set)) 2> /dev/null || :
	return ${OK}
}

LoadConfig() {
	local rule_check_title \
		rule_check_state \
		rule_check_type \
		rule_check_app_name \
		rule_check_application \
		rule_check_class \
		rule_check_role \
		rule_check_desktop \
		rule_check_is_maximized \
		rule_check_is_maximized_horz \
		rule_check_is_maximized_vert \
		rule_check_is_shaded \
		rule_check_is_sticky \
		rule_check_desktop_size \
		rule_check_desktop_workarea \
		rule_set_delay \
		rule_set_above \
		rule_set_below \
		rule_set_maximized \
		rule_set_maximized_horizontally \
		rule_set_maximized_vertically \
		rule_set_shaded \
		rule_set_sticky \
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
		rule msg="Loading configuration"

	# config variables, default values
	Debug=""
	unset $(awk -F '=' \
		'$1 ~ "^rule[[:digit:]]*_" {print $1}' \
		< <(set)) 2> /dev/null || :

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
		Debug="verbose"
	! printf '%s\n' "${@}" | grep -qsxiF 'xtrace' || \
		Debug="xtrace"
	if [ "${Debug}" = "xtrace" ]; then
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {BASH_XTRACEFD}>> "${LOGFILE}.xtrace"
		set -o xtrace
	else
		set +o xtrace
	fi
	[ -z "${Debug}" ] || {
		[ "${Debug}" = "xtrace" ] || \
			Debug="verbose"
		_log "debug level is \"${Debug}\""
	}

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
			if sort < <(grep -se "^rule${rule}_.*=" \
			< <(set)); then
				grep -qse "^rule${rule}_check_.*=" \
				< <(set) || \
					LogPrio="err" _log "hasn't defined any check property for rule ${rule}"
				grep -qsve "^rule${rule}_set_delay=" \
				< <(grep -se "^rule${rule}_set_.*=" \
				< <(set)) || \
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

readonly LF=$'\n' TAB=$'\t' OK=0 ERR=1 NONE=0 \
	PATTERN_YES="^(y.*|true|on|1|enable.*)$" \
	PATTERN_NO="^(n.*|false|off|0|disable.*)$" \
	PATTERN_FIXEDSIZE="^[0-9]+x[0-9]+$" \
	AFFIRMATIVE="y" \
	NEGATIVE="n"

:
