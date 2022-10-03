#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.23 $
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

_trim() {
	printf '%s\n' "${@}" | \
		sed -re "s/^[[:blank:]]*(.*)[[:blank:]]*$/\1/"
}

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

_lock_release() {
	local lockfile="${1}.lock"
	rm -f "${lockfile}"
}

_lock_acquire() {
	local lockfile="${1}.lock" \
		pid="${2}" \
		pidw
	while (set -o noclobber;
	! echo ${pid} > "${lockfile}" 2> /dev/null); do
		sleep 1 &
		pidw=${!}
		kill -s 0 $(cat "${lockfile}") 2> /dev/null || {
			rm -f "${lockfile}"
			kill ${pidw} 2> /dev/null || :
		}
		wait ${pidw} || :
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
	w="$(tr -s '[:blank:],:x' ' ' <<< "${w,,}")"
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
		val="${2,,}"
	if [[ "${val}" =~ ${PATTERN_FIXEDSIZE} ]]; then
		eval ${var}=\'${val}\'
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

DesktopCurrent() {
	xdotool get_desktop
}

DesktopSize() {
	local desktop="${1:-"-1"}" \
		desktopGeometry desktopViewPos desktopWorkareaX_Y desktopWorkareaWxH dummy
	[ ${desktop} -ge 0 ] || \
		desktop=$(DesktopCurrent)
	read -r desktopNum dummy \
	dummy desktopGeometry \
	dummy desktopViewPos \
	dummy desktopWorkareaX_Y desktopWorkareaWxH \
	desktopName \
		< <(awk -v desktop="${desktop}" \
		'$1 == desktop {print $0; exit}' < <(wmctrl -d)) || \
			return ${ERR}
	desktopWidth="$(cut -f 1 -s -d 'x' <<< "${desktopGeometry}")"
	desktopHeight="$(cut -f 2 -s -d 'x' <<< "${desktopGeometry}")"
	desktopViewPosX="$(cut -f 1 -s -d ',' <<< "${desktopViewPos}")"
	desktopViewPosY="$(cut -f 2 -s -d ',' <<< "${desktopViewPos}")"
	desktopWorkareaX="$(cut -f 1 -s -d ',' <<< "${desktopWorkareaX_Y}")"
	desktopWorkareaY="$(cut -f 2 -s -d ',' <<< "${desktopWorkareaX_Y}")"
	desktopWorkareaW="$(cut -f 1 -s -d 'x' <<< "${desktopWorkareaWxH}")"
	desktopWorkareaH="$(cut -f 2 -s -d 'x' <<< "${desktopWorkareaWxH}")"
}

DesktopsCount() {
	xdotool get_num_desktops
}

DesktopSetCurrent() {
	local windowId="${1}" \
		desktop="${2}"
	[ ${desktop} -eq $(DesktopCurrent) ] || \
		xdotool set_desktop ${desktop} 2> /dev/null || {
			LogPrio="err" \
				_log "window ${windowId}: can't set current desktop to ${desktop}"
			return ${ERR}
		}
}

WindowDesktop() {
	local windowId="${1}" \
		desktop
	desktop="$(xdotool get_desktop_for_window ${windowId} 2> /dev/null)" || :
	[ -n "${desktop}" ] || \
		LogPrio="err" \
			_log "window ${windowId}: can't get desktop for this window"
	printf '%d\n' ${desktop:-"-1"}
}

WindowGeometry() {
	local windowId="${1}"
	eval $(sed -e '/^WIDTH=/s//windowWidth=/' \
			-e '/^HEIGHT=/s//windowHeight=/' \
			-e '/^X=/s//windowX=/' \
			-e '/^Y=/s//windowY=/' \
			-e '/^SCREEN=/s//windowScreen=/' \
			< <(xdotool getwindowgeometry --shell ${windowId}))
}

WindowExists() {
	local windowId="$(printf '0x%0x' "${1}")"
	xprop -root "_NET_CLIENT_LIST" | \
	cut -f 2- -s -d '#' | \
	tr -s '[:blank:],' ' ' | \
	grep -qswF "${windowId}" || {
		_log "window ${windowId}: can't set up this window, has been closed"
		return ${ERR}
	}
}

WindowActive() {
	printf '0x%0x\n' \
		$(xdotool getactivewindow 2>/dev/null || \
		echo 0)
}

WindowProp() {
	xprop -len 1024 -id "${@}"
}

WindowPropAtom() {
	local windowId="${1}" \
		atom="${2}"
	WindowProp ${windowId} "${atom}" | \
		sed -nre '\|.*[=] (.*)$|!{q1};s//\1/p'
}

WindowState() {
	local windowId="${1}"
	WindowProp ${windowId} "WM_STATE" | \
		awk '$0 ~ "window state:" {print $NF}'
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
	[ $(printf '%s\n' ${wmstate} | \
	grep -s --count -wF "$(printf '%s\n' "${@}")") -eq ${#} ]
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
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

IsWindowMaximizedHorz() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_MAXIMIZED_HORZ' || {
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

IsWindowMaximizedVert() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_MAXIMIZED_VERT' || {
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

IsWindowFullscreen() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_FULLSCREEN' || {
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

IsWindowMinimized() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_HIDDEN' || {
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

IsWindowShaded() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_SHADED' || {
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

IsWindowDecorated() {
	local windowId="${1}" \
		answer="${2:-}"
	! IsWindowNetstateActive ${windowId} '_OB_WM_STATE_UNDECORATED' || {
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

IsWindowSticky() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_STICKY' || {
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

IsWindowAbove() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_ABOVE' || {
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

IsWindowBelow() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetstateActive ${windowId} '_NET_WM_STATE_BELOW' || {
		[ -z "${answer}" ] || \
			echo "${NEGATIVE}"
		return ${ERR}
	}
	[ -z "${answer}" ] || \
		echo "${AFFIRMATIVE}"
}

RuleLine() {
	local prop="${1}" \
		val="${2}"
	[ -n "${val}" ] || {
		LogPrio="err" _log "Rule ${Rules}: Property \"${prop}\" has not a value"
		return ${ERR}
	}
	case "${prop}" in
	check_title | \
	check_state | \
	check_type | \
	check_app_name | \
	check_application | \
	check_class | \
	check_role)
		eval rule${Rules}_${prop}=\'${val}\'
		;;
	check_desktop | \
	check_desktops)
		_check_natural "rule${Rules}_${prop}" "${val}"
		;;
	check_is_maximized | \
	check_is_maximized_horz | \
	check_is_maximized_vert | \
	check_is_fullscreen | \
	check_is_minimized | \
	check_is_shaded | \
	check_is_decorated | \
	check_is_sticky)
		_check_yn "rule${Rules}_${prop}" "${val}"
		;;
	check_desktop_size | \
	check_desktop_workarea)
		_check_fixedsize "rule${Rules}_${prop}" "${val}"
		;;
	check_others)
		_check_y "rule${Rules}_${prop}" "${val}"
		;;
	set_focus | \
	set_closed | \
	set_killed)
		_check_y "rule${Rules}_$((++ruleIndex))_${prop}" "${val}"
		;;
	set_delay)
		_check_natural val ${NONE}
		[ "${val}" -eq ${NONE} ] || \
			eval rule${Rules}_$((++ruleIndex))_${prop}=\'${val}\'
		;;
	set_active_desktop | \
	set_desktop)
		_check_natural val ${NONE}
		eval rule${Rules}_$((++ruleIndex))_${prop}=\'${val}\'
		;;
	set_position | \
	set_size | \
	set_tile | \
	set_pointer)
		val="$(tr -s '[:blank:],' ' ' <<< "${val,,}")"
		if [ "$(wc -w <<< "${val}")" != 2 ]; then
			_log "Property \"${prop}\" invalid value \"${val}\""
		else
			_check_integer_pair val "x" "y"
			eval rule${Rules}_$((++ruleIndex))_${prop}=\'${val}\'
		fi
		;;
	set_maximized | \
	set_maximized_horizontally | \
	set_maximized_vertically | \
	set_minimized | \
	set_fullscreen | \
	set_sticky | \
	set_shaded | \
	set_decorated | \
	set_pinned | \
	set_above | \
	set_below)
		_check_yn "rule${Rules}_$((++ruleIndex))_${prop}" "${val}"
		;;
	*)
		_log "Property \"${prop}\" is not implemented yet"
		return ${ERR}
		;;
	esac
}

ReadConfig() {
	local foundParm="" foundRule="" ruleIndex
	Rules=${NONE}
	rm -f "${TILESFILE}"*
	: > "${TILESFILE}"
	while read -r line; do
		[ -n "${line}" ] && \
		[ "${line:0:1}" != "#" ] || \
			continue
		if grep -qsxiEe 'parameters[[:blank:]]*\{[[:blank:]]*' <<< "${line}"; then
			printf '%s\n' "Parameters {"
			[ -z "${foundRule}" ] || \
				return ${ERR}
			foundParm="y"
		elif grep -qsxiEe 'rule[[:blank:]]*\{[[:blank:]]*' <<< "${line}"; then
			printf '%s\n' "Rule {"
			[ -z "${foundParm}" ] || \
				return ${ERR}
			foundRule="y"
			let Rules++,1
			ruleIndex=0
		elif grep -qsxiEe '\}[[:blank:]]*' <<< "${line,,}"; then
			printf '%s\n' "}" ""
			foundParm=""
			foundRule=""
		else
			printf '\t%s\n' "${line}"
			if [ -n "${foundParm}" ]; then
				case "$(_trim "${line,,}")" in
				debug=*)
					Debug="$(_unquote "$(_trim "$(cut -f 2- -s -d '=' <<< "${line}")")")"
					;;
				emptylist)
					EmptyList="y"
					;;
				*)
					return ${ERR}
					;;
				esac
			elif [ -n "${foundRule}" ]; then
				RuleLine \
				"$(cut -f 1 -d '=' <<< "${line,,}")" \
				"$(_unquote "$(_trim "$(cut -f 2- -s -d '=' <<< "${line}")")")" || \
					return ${ERR}
			else
				return ${ERR}
			fi
		fi
	done < "${config}" >> "${LOGFILE}"
	[ -z "${foundParm}" -a -z "${foundRule}" ] || \
		return ${ERR}
}

LoadConfig() {
	local rule dbg config emptylist \
		msg="Loading configuration"

	# config variables, default values
	Debug="verbose"
	dbg=""
	EmptyList=""
	emptylist=""
	config="${HOME}/.config/${APPNAME}/config.txt"
	IgnoreWindowTypes="desktop|dock"
	unset $(awk -F '=' \
		'$1 ~ "^rule[[:digit:]]*_" {print $1}' \
		< <(set)) 2> /dev/null || :

	_log "${msg}"

	for option in "${@}"; do
		[ -z "${option,,}" ] || \
			case "${option,,}" in
			xtrace)
				dbg="xtrace"
				;;
			config=*)
				config="$(cut -f 2- -s -d '=' <<< "${option}")"
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

	[ -f "${config}" -a -s "${config}" ] || {
		LogPrio="err" _log "Invalid config file:" \
			"\"${config}\""
		exit ${ERR}
	}

	ReadConfig || {
		LogPrio="err" _log "Syntax error in config file:" \
			"\"${config}\""
		exit ${ERR}
	}

	Debug="${dbg:-${Debug:-}}"
	EmptyList="${emptylist:-${EmptyList:-}}"

	[ -n "${EmptyList}" ] && \
		WindowIds="" || \
		WindowIds="$(tr -s '[:blank:],' ' ' \
			< <(cut -f 2- -s -d '#' \
			< <(xprop -root "_NET_CLIENT_LIST")))"

	set +o xtrace
	if [ "${Debug}" = "xtrace" ]; then
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {BASH_XTRACEFD}>> "${LOGFILE}.xtrace"
		exec >> "${LOGFILE}.xtrace" 2>&1
		set -o xtrace
	else
		exec >> "${LOGFILE}" 2>&1
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
			set | \
			grep -se "^rule${rule}_check_.*=" || \
				LogPrio="err" \
				_log "hasn't defined any property to check for rule ${rule}"
			set | \
			grep -sEe "^rule${rule}_[[:digit:]]+_set_.*=" | \
			sort --numeric --field-separator="_" --key 2,2 || \
				LogPrio="warn" \
				_log "hasn't defined any property to set for rule ${rule}"
		done
		echo
	fi >> "${LOGFILE}"

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
