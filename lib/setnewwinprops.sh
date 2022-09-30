#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.11 $
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
		val="${2}" \
		dft="${3:-${AFFIRMATIVE}}"
	if [[ "${val,,}" =~ ${PATTERN_YES} ]]; then
		eval ${var}=\'${AFFIRMATIVE}\'
	elif [[ "${val,,}" =~ ${PATTERN_NO} ]]; then
		eval ${var}=\'${NEGATIVE}\'
	else
		LogPrio="warn" _log "Variable \"${var}\" invalid value \"${val}\"," \
			"assuming default \"${dft}\""
		eval ${var}=\'${dft}\'
	fi
}

_check_y() {
	local var="${1}" \
		val="${2}" \
		dft="${3:-${AFFIRMATIVE}}"
	[[ "${val,,}" =~ ${PATTERN_YES} ]] || \
		LogPrio="warn" _log "Variable \"${var}\" invalid value \"${val}\"," \
			"assuming default \"${dft}\""
	eval ${var}=\'${dft}\'
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
	local xroot t=0
	while ! xroot="$(xprop -root _NET_SUPPORTING_WM_CHECK | \
	awk '$NF ~ "^0x[0-9A-Fa-f]+$" {print $NF; rc=-1; exit}
	END{exit rc+1}')" && \
	[ $((t++)) -lt 5 ]; do
		sleep 1
	done 2> /dev/null
	[ -n "${xroot}" ] && \
		echo "${xroot}" || \
		return ${ERR}
}

AlreadyRunning() {
	local pid
	[ -e "${PIDFILE}" -a -f "${PIDFILE}" -a -s "${PIDFILE}" ] && \
	pid="$(cat "${PIDFILE}")" 2> /dev/null && \
	kill -s 0 "${pid}" 2> /dev/null || \
		return ${ERR}
	echo "Info: ${APPNAME} is running in pid ${pid}" >&2
	echo ${pid}
}

DesktopSize() {
	awk '$2 == "*" {print $4; exit}' < <(wmctrl -d)
#	awk -F '=' \
#	'$1 == "WIDTH" {width=$2}
#	$1 == "HEIGHT" {height=$2}
#	END{if (width) print width "x" height
#		else exit 1}' \
#		< <(xdotool getdisplaygeometry --shell)
}

DesktopWorkarea() {
	awk '$2 == "*" {print $9; exit}' < <(wmctrl -d)
}

DesktopCurrent() {
	xdotool get_desktop
}

DesktopsCount() {
	xdotool get_num_desktops
}

DesktopSetCurrent() {
	local windowId="${1}" \
		desktop="${2}"
	xdotool set_desktop ${desktop} 2> /dev/null || {
		LogPrio="err" \
			_log "window ${windowId}: can't set current desktop to ${desktop}"
		return ${ERR}
	}
}

WindowDesktop() {
	local windowId="${1}"
	xdotool get_desktop_for_window ${windowId} 2> /dev/null || {
		LogPrio="err" \
			_log "window ${windowId}: can't get desktop for this window"
		printf '%s\n' "-2"
	}
}

WindowGeometry() {
	eval $(sed -e '/^WIDTH=/s//windowWidth=/' \
			-e '/^HEIGHT=/s//windowHeight=/' \
			-e '/^X=/s//windowX=/' \
			-e '/^Y=/s//windowY=/' \
			-e '/^SCREEN=/s//windowScreen=/' \
			< <(xdotool getwindowgeometry --shell ${windowId}))
}

WindowExists() {
	local windowId="$(printf '0x%0x' "${1}")"
	grep -qswF "${windowId}" < <(tr -s ' ,' ' ' \
	< <(cut -f 2- -s -d '#' \
	< <(xprop -root "_NET_CLIENT_LIST"))) || {
		_log "window ${windowId}: can't set up this window, has been closed"
		return ${ERR}
	}
}

WindowActive() {
	printf '0x%0x\n' \
		$(xdotool getactivewindow 2>/dev/null || \
		echo 0)
}

WindowSetActive() {
	local windowId="${1}" \
		desktop
	desktop="$(WindowDesktop ${windowId})"
	[ ${desktop} -ge 0 ] && \
	[ ${desktop} -eq $(DesktopCurrent) ] || \
		DesktopSetCurrent ${windowId} ${desktop} || :
	[[ $(WindowActive) -eq ${windowId} ]] || \
		xdotool windowactivate --sync ${windowId} || 
			WindowExists ${windowId} || \
				return ${ERR}
}

WindowTapKeys() {
	local windowId="${1}" \
		xkbmap key first
	shift
	xkbmap="$(setxkbmap -query | \
		sed -nre '\|^options| s||option|' \
		-e '\|([^:[:blank:]]+)[:[:blank:]]+(.*)| s||-\1 \2|p')"
	setxkbmap us dvorak -rules xorg -model pc105 -option
	first="y"
	for key in "${@}"; do
		[ -n "${first}" ] || \
			sleep 1
		first=""
		WindowSetActive ${windowId} || \
			break
		xdotool key --clearmodifiers "${key}"
	done
	setxkbmap ${xkbmap}
}

WindowProp() {
	xprop -len 1024 -id "${@}"
}

WindowPropAtom() {
	local windowId="${1}" \
		atom="${2}"
	sed -nre '\|.*[=] (.*)$|!{q1};s//\1/p' \
		< <(WindowProp ${windowId} "${atom}")
}

WindowState() {
	local windowId="${1}"
	awk '$0 ~ "window state:" {print $NF}' \
		< <(WindowProp ${windowId} "WM_STATE")
}

WindowNetstate() {
	local windowId="${1}"
	WindowPropAtom ${windowId} "_NET_WM_STATE"
}

IsWindowNetstateActive() {
	local windowId="${1}" wmstate
	wmstate="$(WindowNetstate ${windowId})" || \
		return ${ERR}
	shift
	[ $(grep -s --count -wF "$(printf '%s\n' "${@}")" \
	< <(printf '%s\n' ${wmstate})) -eq ${#} ]
}

WindowTitle() {
	local windowId="${1}" name
	name="$(xdotool getwindowname ${windowId})"
	[ -n "${name}" ] && \
		printf '%s\n' "${name}" || \
		return ${ERR}
}

WindowAppName() {
	local windowId="${1}"
	_unquote "$(WindowPropAtom ${windowId} "_OB_APP_NAME")"
}

WindowType() {
	local windowId="${1}"
	WindowPropAtom ${windowId} "_NET_WM_WINDOW_TYPE"
}

WindowApplication() {
	local windowId="${1}"
	ps -ho cmd "$(xdotool getwindowpid ${windowId})" || \
		return ${ERR}
}

WindowClass() {
	local windowId="${1}"
	WindowPropAtom ${windowId} "WM_CLASS"
}

WindowRole() {
	local windowId="${1}"
	WindowPropAtom ${windowId} "WM_WINDOW_ROLE"
}

IsWindowMaximized() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} \
	'_NET_WM_STATE_MAXIMIZED_HORZ' \
	'_NET_WM_STATE_MAXIMIZED_VERT' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

IsWindowMaximizedHorz() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_MAXIMIZED_HORZ' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

IsWindowMaximizedVert() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_MAXIMIZED_VERT' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

IsWindowFullscreen() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_FULLSCREEN' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

IsWindowMinimized() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_MINIMIZED' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

IsWindowShaded() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_SHADED' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

IsWindowDecorated() {
	local windowId="${1}" \
		answer="${2:-}"
	! IsWindowNetstateActive ${windowId} '_OB_WM_STATE_UNDECORATED' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

IsWindowSticky() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_STICKY' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

IsWindowAbove() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_ABOVE' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

IsWindowBelow() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_BELOW' || {
		echo "${answer:+${NEGATIVE}}"
		return ${ERR}
	}
	echo "${answer:+${AFFIRMATIVE}}"
}

RuleAppend() {
	let Rules++,1
	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		[ -n "${val}" ] || {
			LogPrio="err" _log "Rule ${Rules}: Property \"${prop}\" has not a value"
			continue
		}
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
		rule_check_is_fullscreen)
			_check_yn "rule${Rules}_check_is_fullscreen" "${val}"
			;;
		rule_check_is_minimized)
			_check_yn "rule${Rules}_check_is_minimized" "${val}"
			;;
		rule_check_is_shaded)
			_check_yn "rule${Rules}_check_is_shaded" "${val}"
			;;
		rule_check_is_decorated)
			_check_yn "rule${Rules}_check_is_decorated" "${val}"
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
		rule_check_desktops)
			_check_natural "rule${Rules}_check_desktops" "${val}"
			;;
		rule_set_ignore)
			_check_y "rule${Rules}_set_ignore" "${val}"
			;;
		rule_set_continue)
			_check_y "rule${Rules}_set_continue" "${val}"
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
		rule_set_maximized)
			_check_yn "rule${Rules}_set_maximized" "${val}"
			;;
		rule_set_maximized_horizontally)
			_check_yn "rule${Rules}_set_maximized_horizontally" "${val}"
			;;
		rule_set_maximized_vertically)
			_check_yn "rule${Rules}_set_maximized_vertically" "${val}"
			;;
		rule_set_minimized)
			_check_yn "rule${Rules}_set_minimized" "${val}"
			;;
		rule_set_fullscreen)
			_check_yn "rule${Rules}_set_fullscreen" "${val}"
			;;
		rule_set_sticky)
			_check_yn "rule${Rules}_set_sticky" "${val}"
			;;
		rule_set_shaded)
			_check_yn "rule${Rules}_set_shaded" "${val}"
			;;
		rule_set_decorated)
			_check_yn "rule${Rules}_set_decorated" "${val}"
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
		rule_set_active_desktop)
			_check_natural val ${NONE}
			eval rule${Rules}_set_active_desktop=\'${val}\'
			;;
		rule_set_desktop)
			_check_natural val ${NONE}
			eval rule${Rules}_set_desktop=\'${val}\'
			;;
		rule_set_closed)
			_check_y "rule${Rules}_set_closed" "${val}"
			;;
		rule_set_killed)
			_check_y "rule${Rules}_set_killed" "${val}"
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
			rule_check_is_maximized | \
			rule_check_is_maximized_horz | \
			rule_check_is_maximized_vert | \
			rule_check_is_fullscreen | \
			rule_check_is_minimized | \
			rule_check_is_shaded | \
			rule_check_is_decorated | \
			rule_check_is_sticky | \
			rule_check_desktop_size | \
			rule_check_desktop_workarea | \
			rule_check_desktops)
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
		rule_check_is_fullscreen \
		rule_check_is_minimized \
		rule_check_is_shaded \
		rule_check_is_decorated \
		rule_check_is_sticky \
		rule_check_desktop_size \
		rule_check_desktop_workarea \
		rule_check_desktops \
		rule_set_ignore \
		rule_set_continue \
		rule_set_delay \
		rule_set_position \
		rule_set_size \
		rule_set_maximized \
		rule_set_maximized_horizontally \
		rule_set_maximized_vertically \
		rule_set_fullscreen \
		rule_set_minimized \
		rule_set_shaded \
		rule_set_decorated \
		rule_set_sticky \
		rule_set_focus \
		rule_set_above \
		rule_set_below \
		rule_set_active_desktop \
		rule_set_desktop \
		rule_set_closed \
		rule_set_killed \
		rule dbg config emptylist \
		msg="Loading configuration"

	# config variables, default values
	Debug="verbose"
	dbg=""
	unset $(awk -F '=' \
		'$1 ~ "^rule[[:digit:]]*_" {print $1}' \
		< <(set)) 2> /dev/null || :
	IgnoreWindowTypes="DESKTOP,DOCK"
	emptylist=""
	config="${HOME}/.config/${APPNAME}/config.txt"

	_log "${msg}"

	for option in "${@}"; do
		[ -z "${option,,}" ] || \
			case "${option,,}" in
			xtrace)
				dbg="xtrace"
				;;
			config=*)
				eval config=\'$(cut -f 2- -s -d '=' <<< "${option}")\'
				;;
			debug|verbose)
				dbg="verbose"
				;;
			silent)
				dbg=""
				;;
			emptylist)
				emptylist="y"
				;;
			*)
				LogPrio="warn" _log "Invalid command line option:" \
					"\"${option}\""
				;;
			esac
	done

	[ -n "${emptylist}" ] && \
		WindowIds="" || \
		WindowIds="$(tr -s ' ,' ' ' \
			< <(cut -f 2- -s -d '#' \
			< <(xprop -root "_NET_CLIENT_LIST")))"

	Rules=${NONE}
	[ -s "${config}" ] && \
		. "${config}" || {
			LogPrio="err" _log "Invalid config file:" \
				"\"${config}\""
			exit ${ERR}
		}

	Debug="${dbg:-${Debug:-}}"

	if [ "${Debug}" = "xtrace" ]; then
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {BASH_XTRACEFD}>> "${LOGFILE}.xtrace"
		set -o xtrace
	else
		set +o xtrace
	fi

	if [ -n "${Debug}" -o ${#} -gt ${NONE} ]; then
		msg="daemon's command line"
		[ ${#} -gt ${NONE} ] && \
			msg="${msg} options:$(printf ' "%s"' "${@}")" || \
			msg="${msg} is empty"
		_log "${msg}"
	fi

	[ -z "${Debug}" ] || {
		[ "${Debug}" = "xtrace" ] || \
			Debug="verbose"
		_log "debug level is \"${Debug}\""
	}

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
				grep -qsvEe "^rule${rule}_set_(delay|continue)=" \
				< <(grep -se "^rule${rule}_set_.*=" \
				< <(set)) || \
					LogPrio="err" _log "hasn't defined any property to set for rule ${rule}"
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
