#!/bin/bash

#************************************************************************
#  DesktopArrange
#
#  Arrange Linux worskpaces
#  according to a set of configurable rules.
#
#  $Revision: 0.32 $
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

# priority: info notice warn err debug
_log() {
	local msg \
		LogPrio="${LogPrio:-"notice"}"
	if [ "${LogPrio}" = "info" -o "${LogPrio}" = "warn" -o "${LogPrio}" = "err" ] || \
	[ "${LogPrio}" = "notice" -a "${Debug}" != "info" ] || \
	[ "${LogPrio}" = "debug" -a \
	\( "${Debug}" = "debug" -o "${Debug}" = "xtrace" \) ]; then
		msg="$(_datetime) ${LogPrio}: ${@}"
		printf '%s\n' "${msg}" >> "${LOGFILE}"
	fi
	LogPrio=""
}

_lock_active() {
	local lockfile="${1}.lock" \
		pid="${2}"
	[ ! -e "${lockfile}" ] || \
	[ $(cat "${lockfile}") -ne ${pid} ] || \
		echo "y"
}

_lock_release() {
	local lockfile="${1}.lock" \
		pid="${2}"
	if [ ! -e "${lockfile}" ]; then
		LogPrio="debug" \
		_log "_lock_release: file \"${lockfile}\" does not exist"
	elif [ $(cat "${lockfile}") != ${pid} ]; then
		LogPrio="debug" \
		_log "_lock_release: another pid releases \"${lockfile}\""
	fi
	rm -f "${lockfile}"
}

_lock_acquire() {
	local lockfile="${1}.lock" \
		pid="${2}" \
		pidw
	[ ! -e "${lockfile}" ] || \
	[ $(cat "${lockfile}") != ${pid} ] || \
		LogPrio="debug" \
		_log "_lock_acquire: same pid \"${pid}\"" \
			"requests already existent lock \"${lockfile}\""
	while (set -o noclobber;
	! echo ${pid} > "${lockfile}") 2> /dev/null; do
		sleep 1 &
		pidw=${!}
		[ "${Debug}" != "xtrace" ] || \
			LogPrio="debug" \
			_log "_lock_acquire: pid \"${pid}\" is waiting for a lock \"${lockfile}\""
		kill -s 0 $(cat "${lockfile}") 2> /dev/null || {
			LogPrio="debug" \
			_log "_lock_acquire: pid \"$(cat "${lockfile}")\"" \
				"has not released his lock \"${lockfile}\""
			rm -f "${lockfile}"
			kill ${pidw} 2> /dev/null || :
		}
		wait ${pidw} || :
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
		LogPrio="err" \
		_log "Config:" \
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
		d="${2:-0}" \
		prefix="${3:-}" \
		v="" w rc=${OK}
	eval w=\"\${${n}:-}\"
	let "v=${w}" 2> /dev/null || \
		rc=${?}
	if [ ${rc} -gt 1 ] || [ -z "${v}" ] || [ "${v}" -lt 0 ]; then
		LogPrio="err" \
		_log "Config error:" \
			"Invalid integer value \"${w}\" for \"${n}\"," \
			"assuming default \"${d}\""
		v="${d}"
	fi
	let "${n}=${v},1"
	[ -z "{prefix}" ] || \
		eval "${n}=${prefix}${v}"
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
		LogPrio="warn" \
		_log "Variable \"${var}\" invalid value \"${val}\"," \
			"assuming default \"${dft}\""
		eval ${var}=\'${dft}\'
	fi
}

_check_y() {
	local var="${1}" \
		val="${2}" \
		dft="${3:-${AFFIRMATIVE}}"
	[[ "${val,,}" =~ ${PATTERN_YES} ]] || \
		LogPrio="warn" \
		_log "Variable \"${var}\" invalid value \"${val}\"," \
			"assuming default \"${dft}\""
	eval ${var}=\'${dft}\'
}

_check_fixedsize() {
	local var="${1}" \
		val="${2,,}" \
		d="${3:-0}" \
		prefix="${4:-}"
	if [[ "${val}" =~ ${PATTERN_FIXEDSIZE} ]]; then
		eval ${var}=\'${prefix}${val}\'
	else
		LogPrio="warn" \
		_log "Variable \"${var}\" invalid value \"${prefix}${val}\""
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
	pid="$(cat "${PIDFILE}" 2> /dev/null)" && \
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
		ruleType="${2}" \
		rule="${3}" \
		desktop="${4}"
	[ ${desktop} -eq $(DesktopCurrent) ] || \
		xdotool set_desktop ${desktop} 2> /dev/null || {
			LogPrio="err" \
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"can't set current desktop to ${desktop}"
			return ${ERR}
		}
}

WindowStateAction() {
	local state="${1}"
	awk -v state="${state}" -v s="${TAB}" \
		'BEGIN{RS=s}
		$2 == state {print $1; rc=-1; exit}
		END{exit rc+1}' <<< "${ACTIONSTATES}"
}

WindowDesktop() {
	local windowId="${1}" \
		ruleType="${2:-}" \
		rule="${3:-}" \
		desktop
	desktop="$(xdotool get_desktop_for_window ${windowId} 2> /dev/null)" || :
	[ -n "${desktop}" ] || \
		LogPrio="err" \
		_log "window ${windowId}${rule:+" ${ruleType} ${rule}"}:" \
			"can't get desktop for this window"
	printf '%d\n' ${desktop:-"-2"}
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
		LogPrio="err" \
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
		sed -nre '\|.*[=] (.*)$|!{q1};{s//\1/;s/[[:blank:],]+/ /g;p}'
}

WindowState() {
	local windowId="${1}"
	WindowProp ${windowId} "WM_STATE" | \
		awk '$0 ~ "window state:" {print $NF}'
}

WindowNetState() {
	local windowId="${1}"
	WindowPropAtom ${windowId} "_NET_WM_STATE"
}

WindowNetAllowedActions() {
	local windowId="${1}"
	WindowPropAtom ${windowId} "_NET_WM_ALLOWED_ACTIONS"
}

IsWindowNetStateActive() {
	local windowId="${1}" \
		netState netAllowedActions state action
	netState="$(WindowNetState ${windowId})" || \
		return ${ERR}
	netAllowedActions="$(WindowNetAllowedActions ${windowId})" || \
		return ${ERR}
	shift
	for state in "${@}"; do
		action="$(WindowStateAction "${state}")" || \
			return 2
		grep -qswF "${action}" <<< "${netAllowedActions}" || \
			return 2
	done
	[ $(printf '%s\n' ${netState} | \
	grep -s --count -wF "$(printf '%s\n' "${@}")") -eq ${#} ]
}

IsWindowNetStateKnown() {
	local windowId="${1}" \
		answer="${2:-}" \
		rc=0
	shift 2
	IsWindowNetStateActive ${windowId} "${@}" || \
		rc=${?}
	[ -n "${answer}" ] || \
		return ${rc}
	case ${rc} in
	1)
		echo "${NEGATIVE}"
		;;
	2)
		echo "${UNKNOWN}"
		;;
	*)
		echo "${AFFIRMATIVE}"
		;;
	esac
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
	WindowPropAtom ${windowId} "_NET_WM_WINDOW_TYPE" | \
		sed -re '/_NET_WM_WINDOW_TYPE_/s///g'
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
	IsWindowNetStateKnown ${windowId} "${answer}" \
	'_NET_WM_STATE_MAXIMIZED_HORZ' \
	'_NET_WM_STATE_MAXIMIZED_VERT' || \
		return ${?}
}

IsWindowMaximized_horz() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetStateKnown ${windowId} "${answer}" \
	'_NET_WM_STATE_MAXIMIZED_HORZ' || \
		return ${?}
}

IsWindowMaximized_vert() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetStateKnown ${windowId} "${answer}" \
	'_NET_WM_STATE_MAXIMIZED_VERT' || \
		return ${?}
}

IsWindowFullscreen() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetStateKnown ${windowId} "${answer}" \
	'_NET_WM_STATE_FULLSCREEN' || \
		return ${?}
}

IsWindowMinimized() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetStateKnown ${windowId} "${answer}" \
	'_NET_WM_STATE_HIDDEN' || \
		return ${?}
}

IsWindowShaded() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetStateKnown ${windowId} "${answer}" \
	'_NET_WM_STATE_SHADED' || \
		return ${?}
}

IsWindowUndecorated() {
	local windowId="${1}" \
		answer="${2:-}" \
		decoration
	decoration="$(toggle-decorations -s ${windowId})" || {
		[ -n "${answer}" ] && \
			echo "${UNKNOWN}" || \
			return 2
	}
	if [ ${decoration##* } -ne 0 ]; then
		[ -n "${answer}" ] && \
			echo "${NEGATIVE}" || \
			return ${ERR}
	else
		[ -n "${answer}" ] && \
			echo "${AFFIRMATIVE}" || \
			return ${OK}
	fi
}

IsWindowSticky() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetStateKnown ${windowId} "${answer}" \
	'_NET_WM_STATE_STICKY' || \
		return ${?}
}

IsWindowAbove() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetStateKnown ${windowId} "${answer}" \
	'_NET_WM_STATE_ABOVE' || \
		return ${?}
}

IsWindowBelow() {
	local windowId="${1}" \
		answer="${2:-}"
	IsWindowNetStateKnown ${windowId} "${answer}" \
	'_NET_WM_STATE_BELOW' || \
		return ${?}
}

RuleLine() {
	local ruleType="${1}" \
		ruleNumber="${2}" \
		line="${3}" \
		prop val \
		v deselected indexToSet indexToSelect

	prop="$(sed -nr -e '/^(select|deselect|set|unset)[[:blank:]]+/s//\1_/' \
		-e '/^([^[:blank:]=]+).*/s//\1/p' \
		<<< "${line,,}")"
	! sed -nr -e '/^(select|deselect|set|unset)[[:blank:]]+/!q1' \
	<<< "${line,,}" || \
		line="$(sed -r \
		-e '/^[^[:blank:]]+[[:blank:]]+/s///' \
		<<< "${line}")"
	val="$(_unquote "$(_trim "$( \
		sed -nre '/^[^[:blank:]=]+[[:blank:]=]+(.*)/s//\1/p' \
		<<< "${line}")")")"

	let "indexToSet=index${ruleType^}Set,1 "
	let "indexToSelect=index${ruleType^}Select,1"
	[ -n "${prop}" ] || \
		return ${OK}
	if [ "${prop:0:8}" = "deselect" ]; then
		if [ -n "${val}" ];then
			if [ "${val:0:1}" = "!" ];then
				LogPrio="warn" \
				_log "${ruleType} ${ruleNumber}: \"${prop}\" ignoring wrong value \"${val}\"."
				val=""
			else
				prop="${prop:2}"
				val="!${val}"
			fi
		else
			case "${prop:2}" in
			select_stop | \
			select_maximized | \
			select_maximized_horz | \
			select_maximized_vert | \
			select_minimized | \
			select_fullscreen | \
			select_sticky | \
			select_shaded | \
			select_undecorated | \
			select_pinned | \
			select_above | \
			select_below | \
			select_active)
				prop="${prop:2}"
				val="${NEGATIVE}"
				;;
			*)
				LogPrio="err" \
				_log "${ruleType} ${ruleNumber}: \"${prop}\" without a value."
				return ${ERR}
				;;
			esac
		fi
	else
		[ "${prop:0:2}" = "un" ] && \
			p="${prop:2}" || \
			p="${prop}"
		case "${p}" in
		select_stop | \
		set_maximized | \
		set_maximized_horz | \
		set_maximized_vert | \
		set_minimized | \
		set_fullscreen | \
		set_sticky | \
		set_shaded | \
		set_undecorated | \
		set_pinned | \
		set_above | \
		set_below | \
		set_focus | \
		set_closed | \
		set_killed)
			[ "${prop:0:2}" != "un" -o -z "${val}" ] || {
				LogPrio="warn" \
				_log "${ruleType} ${ruleNumber}: \"${prop}\" with a value." \
					"Value \"${val}\" is ignored"
				val=""
			}
			if [ -z "${val}" ]; then
				val="${AFFIRMATIVE}"
				[ "${prop:0:2}" != "un" ] || {
					prop="${prop:2}"
					val="${NEGATIVE}"
				}
			fi
			;;
		*)
			[ "${prop:0:2}" != "un" ] || {
				prop="${prop:2}"
				val="!${val}"
			}
			;;
		esac
	fi
	[ -n "${val}" ] || {
		LogPrio="err" \
		_log "${ruleType} ${ruleNumber}: Property \"${prop}\" has not a value"
		return ${ERR}
	}
	deselected=""
	[ "${val:0:1}" != "!" ] || {
		deselected="!"
		val="${val:1}"
	}
	case "${prop}" in
	select_title | \
	select_state | \
	select_type | \
	select_app_name | \
	select_application | \
	select_class | \
	select_role)
		eval ${ruleType}${ruleNumber}_$((++indexToSelect))_${prop}=\'${deselected}${val}\'
		;;
	select_desktop | \
	select_desktops)
		_check_natural val ${NONE} "${deselected}"
		eval ${ruleType}${ruleNumber}_$((++indexToSelect))_${prop}=\'${val}\'
		;;
	select_desktop_size | \
	select_desktop_workarea)
		_check_fixedsize "${ruleType}${ruleNumber}_$((++indexToSelect))_${prop}" "${val}" "" "${deselected}"
		;;
	select_maximized | \
	select_maximized_horz | \
	select_maximized_vert | \
	select_fullscreen | \
	select_minimized | \
	select_shaded | \
	select_undecorated | \
	select_sticky)
		[ -z "${deselected}" ] || {
			LogPrio="err" \
			_log "${ruleType} ${ruleNumber}: Property \"${prop}\" wrong value \"${val}\""
			return ${ERR}
		}
		_check_yn "${ruleType}${ruleNumber}_$((++indexToSelect))_${prop}" "${val}"
		;;
	select_stop)
		[ -z "${deselected}" ] || {
			LogPrio="err" \
			_log "${ruleType} ${ruleNumber}: Property \"${prop}\" wrong value \"${deselected}${val}\""
			return ${ERR}
		}
		_check_y "${ruleType}${ruleNumber}_0_${prop}" "${val}"
		;;
	set_delay)
		_check_natural val ${NONE}
		[ "${val}" -eq ${NONE} ] || \
			eval ${ruleType}${ruleNumber}_$((++indexToSet))_${prop}=\'${val}\'
		;;
	set_active_desktop | \
	set_desktop)
		_check_natural val ${NONE}
		eval ${ruleType}${ruleNumber}_$((++indexToSet))_${prop}=\'${val}\'
		;;
	set_position | \
	set_size)
		val="$(tr -s '[:blank:],' ' ' <<< "${val,,}")"
		if [ "$(wc -w <<< "${val}")" != 2 ]; then
			LogPrio="err" \
			_log "${ruleType} ${ruleNumber}: Property \"${prop}\" invalid value \"${val}\""
			return ${ERR}
		fi
		_check_integer_pair val "x" "y"
		eval ${ruleType}${ruleNumber}_$((++indexToSet))_${prop}=\'${val}\'
		;;
	set_tiled)
		val="$(tr -s '[:blank:],' ' ' <<< "${val,,}")"
		if [ "$(wc -w <<< "${val}")" != 4 ]; then
			LogPrio="err" \
			_log "${ruleType} ${ruleNumber}: Property \"${prop}\" invalid value \"${val}\""
			return ${ERR}
		fi
		eval ${ruleType}${ruleNumber}_$((++indexToSet))_${prop}=\'${val}\'
		;;
	set_mosaicked)
		val="$(tr -s '[:blank:],' ' ' <<< "${val,,}")"
		if [ "$(wc -w <<< "${val}")" != 2 ]; then
			LogPrio="err" \
			_log "${ruleType} ${ruleNumber}: Property \"${prop}\" invalid value \"${val}\""
			return ${ERR}
		fi
		_check_integer_pair val "0" "0"
		if [ "${val}" = "0 0" ]; then
			val="0 2"
			LogPrio="warn" \
			_log "${ruleType} ${ruleNumber}: Property \"${prop}\" invalid value. Assuming \"${val}\""
		fi
		eval ${ruleType}${ruleNumber}_$((++indexToSet))_${prop}=\'${val}\'
		;;
	set_pointer)
		val="$(tr -s '[:blank:],' ' ' <<< "${val,,}")"
		if [ "$(wc -w <<< "${val}")" != 2 ]; then
			LogPrio="err" \
			_log "${ruleType} ${ruleNumber}: Property \"${prop}\" invalid value \"${val}\""
			return ${ERR}
		fi
		_check_integer_pair val "0" "0"
		eval ${ruleType}${ruleNumber}_$((++indexToSet))_${prop}=\'${val}\'
		;;
	set_tap_keys | \
	set_type_text)
		eval ${ruleType}${ruleNumber}_$((++indexToSet))_${prop}=\'${val}\'
		;;
	set_maximized | \
	set_maximized_horz | \
	set_maximized_vert | \
	set_minimized | \
	set_fullscreen | \
	set_sticky | \
	set_shaded | \
	set_undecorated | \
	set_pinned | \
	set_above | \
	set_below)
		_check_yn "${ruleType}${ruleNumber}_$((++indexToSet))_${prop}" "${val}"
		;;
	set_focus | \
	set_closed | \
	set_killed)
		_check_y "${ruleType}${ruleNumber}_$((++indexToSet))_${prop}" "${val}"
		;;
	*)
		LogPrio="err" \
		_log "${ruleType} ${ruleNumber}: Property \"${prop}\" is not implemented yet"
		return ${ERR}
		;;
	esac
	let "index${ruleType^}Set=indexToSet,1"
	let "index${ruleType^}Select=indexToSelect,1"
}

ReadConfig() {
	local foundParm="" foundRule="" foundGlobalRule="" \
	indexRuleSet indexRuleSelect \
	indexGlobalruleSet indexGlobalruleSelect

	Rules=${NONE}
	GlobalRules=${NONE}
	rm -f "${VARSFILE}"*
	: > "${VARSFILE}"
	while read -r line; do
		[ -n "${line}" ] && \
		[ "${line:0:1}" != "#" ] || \
			continue
		if grep -qsxiEe 'parameters[[:blank:]]*\{[[:blank:]]*' <<< "${line}"; then
			printf '%s\n' "Parameters {"
			[ -z "${foundRule}" -a -z  "${foundGlobalRule}" ] || \
				return ${ERR}
			foundParm="y"
		elif grep -qsxiEe 'rule[[:blank:]]*\{[[:blank:]]*' <<< "${line}"; then
			printf '%s\n' "Rule {"
			[ -z "${foundParm}" -a -z  "${foundGlobalRule}" ] || \
				return ${ERR}
			foundRule="y"
			let Rules++,1
			indexRuleSet=0
			indexRuleSelect=0
		elif grep -qsxiEe 'global[[:blank:]]*rule[[:blank:]]*\{[[:blank:]]*' <<< "${line}"; then
			printf '%s\n' "Global Rule {"
			[ -z "${foundParm}" -a -z "${foundRule}" ] || \
				return ${ERR}
			foundGlobalRule="y"
			let GlobalRules++,1
			indexGlobalruleSet=0
			indexGlobalruleSelect=0
		elif grep -qsxiEe '\}[[:blank:]]*' <<< "${line,,}"; then
			printf '%s\n' "}" ""
			foundParm=""
			foundRule=""
			foundGlobalRule=""
		else
			printf '\t%s\n' "${line}"
			if [ -n "${foundParm}" ]; then
				case "$(_unquote "$(_trim "${line,,}")")" in
				silent)
					Debug="info"
					;;
				verbose)
					Debug="notice"
					;;
				debug)
					Debug="debug"
					;;
				xtrace)
					Debug="xtrace"
					;;
				emptylist)
					EmptyList="y"
					;;
				*)
					LogPrio="err" \
					_log "invalid parameter"
					return ${ERR}
					;;
				esac
			elif [ -n "${foundRule}" ]; then
				RuleLine "rule" "${Rules}" "${line}" || \
					return ${ERR}
			elif [ -n "${foundGlobalRule}" ]; then
				RuleLine "globalrule" "${GlobalRules}" "${line}" || \
					return ${ERR}
			else
				LogPrio="err" \
				_log "have read a line without section"
				return ${ERR}
			fi
		fi
	done < "${config}" >> "${LOGFILE}"
	[ -z "${foundParm}" -a -z "${foundRule}" -a -z "${foundGlobalRule}" ] || {
		LogPrio="err" \
		_log "section" \
		"${foundParm:+"Parameters"}${foundRule:+"Rule"}${foundGlobalRule:+"Global Rule"}" \
		"not closed."
		return ${ERR}
	}
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
	unset $(awk -F '=' \
		'$1 ~ "^rule[[:digit:]]*_" {print $1}' \
		< <(set)) 2> /dev/null || :

	LogPrio="info" \
	_log "${msg}"

	for option in "${@}"; do
		[ -z "${option}" ] || \
			case "${option,,}" in
			silent)
				dbg="info"
				;;
			verbose)
				dbg="verbose"
				;;
			debug)
				dbg="debug"
				;;
			xtrace)
				dbg="xtrace"
				;;
			config=*)
				config="$(cut -f 2- -s -d '=' <<< "${option}")"
				;;
			emptylist)
				emptylist="y"
				;;
			*)
				LogPrio="warn" \
				_log "Invalid command line option:" \
					"\"${option}\""
				;;
			esac
	done

	[ -f "${config}" -a -s "${config}" ] || {
		LogPrio="err" \
		_log "Invalid config file:" \
			"\"${config}\""
		exit ${ERR}
	}

	ReadConfig || {
		LogPrio="err" \
		_log "Syntax error in config file:" \
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

	if [ ${#} -gt ${NONE} ]; then
		msg="daemon's command line"
		[ ${#} -gt ${NONE} ] && \
			msg="${msg} options:$(printf ' "%s"' "${@}")" || \
			msg="${msg} is empty"
		LogPrio="info" \
		_log "${msg}"
	fi

	LogPrio="info" \
	_log "debug level is \"${Debug}\""

	if [ ${GlobalRules} -eq ${NONE} ]; then
		LogPrio="warn" \
		_log "Have not configured any global rule"
	else
		rule=${NONE}
		while [ $((rule++)) -lt ${GlobalRules} ]; do
			echo
			if ! set | \
			grep -sEe "^globalrule${rule}_[[:digit:]]+_set_.*=" | \
			sort --numeric --field-separator="_" --key 2,2; then
				eval globalrule${rule}_0_select_noactions='y'
				LogPrio="warn" \
				_log "global rule ${rule}:" \
					"hasn't defined any property to set"
			fi
			if ! set | \
			grep -sEe "^globalrule${rule}_[[:digit:]]+_select_.*=" | \
			sort --numeric --field-separator="_" --key 2,2; then
				LogPrio="err" \
				_log "global rule ${rule}:" \
					"hasn't defined any property to select"
				exit ${ERR}
			fi
		done
		echo
	fi >> "${LOGFILE}"

	if [ ${Rules} -eq ${NONE} ]; then
		LogPrio="warn" \
		_log "Have not configured any rule"
	else
		rule=${NONE}
		while [ $((rule++)) -lt ${Rules} ]; do
			echo
			if ! set | \
			grep -sEe "^rule${rule}_[[:digit:]]+_set_.*=" | \
			sort --numeric --field-separator="_" --key 2,2; then
				eval rule${rule}_0_select_noactions='y'
				LogPrio="warn" \
				_log "rule ${rule}:" \
					"hasn't defined any property to set"
			fi
			if ! set | \
			grep -sEe "^rule${rule}_[[:digit:]]+_select_.*=" | \
			sort --numeric --field-separator="_" --key 2,2; then
				LogPrio="err" \
				_log "${ruleName} ${rule}:" \
					"hasn't defined any property to select"
				exit ${ERR}
			fi
		done
		echo
	fi >> "${LOGFILE}"

	_log "Configuration reloaded"
	return ${OK}
}

readonly LF=$'\n' TAB=$'\t' SEP=$'\t' OK=0 ERR=1 NONE=0 \
	PATTERN_YES="^(y.*|true|on|1|enable.*)$" \
	PATTERN_NO="^(n.*|false|off|0|disable.*)$" \
	PATTERN_FIXEDSIZE="^[0-9]+x[0-9]+$" \
	AFFIRMATIVE="y" \
	NEGATIVE="n" \
	UNKNOWN="unknown" \
	ACTIONSTATES="_NET_WM_ACTION_ABOVE _NET_WM_STATE_ABOVE\
	_NET_WM_ACTION_BELOW _NET_WM_STATE_BELOW\
	_NET_WM_ACTION_FULLSCREEN _NET_WM_STATE_FULLSCREEN\
	_NET_WM_ACTION_MAXIMIZE_HORZ _NET_WM_STATE_MAXIMIZED_HORZ\
	_NET_WM_ACTION_MAXIMIZE_VERT _NET_WM_STATE_MAXIMIZED_VERT\
	_NET_WM_ACTION_SHADE _NET_WM_STATE_SHADED\
	_NET_WM_ACTION_MINIMIZE _NET_WM_STATE_HIDDEN\
	_NET_WM_ACTION_STICK _NET_WM_STATE_STICKY\
	_NET_WM_ACTION_SKIP_TASKBAR _NET_WM_STATE_SKIP_TASKBAR\
	_NET_WM_ACTION_SKIP_PAGER _NET_WM_STATE_SKIP_PAGER\
	_OB_WM_ACTION_UNDECORATE _OB_WM_STATE_UNDECORATED\
	"
# _NET_WM_STATE_MODAL
# _NET_WM_STATE_DEMANDS_ATTENTION
# ACTIONSTATES: TAB after each record is a list separator

:
