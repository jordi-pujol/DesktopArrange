#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.4 $
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

. /usr/lib/setnewwinprops/setnewwinprops.sh

_exit() {
	local pidsChildren
	trap - EXIT INT HUP
	set +o xtrace
	LogPrio="warn" _log "Exit"
	rm -f "${PIPE}"
	pidsChildren=""; _ps_children
	[ -z "${pidsChildren}" ] || \
		kill -s TERM ${pidsChildren} 2> /dev/null || :
	wait || :
}

WindowSetup() {
	local windowId="${1}" \
		rule="${2}" \
		desktopCurrent desktops \
		desktopWidth desktopHeight \
		windowDesktop windowWidth windowHeight windowX windowY windowScreen \
		prop val

	[ -z "${Debug}" ] || \
		_log "Setting up window ${windowId} using rule num. ${rule}"
	while IFS="=" read -r prop val; do
		_check_natural val 0
		[ ${val} -le 0 ] || {
			[ -z "${Debug}" ] || \
				_log "Waiting ${val} seconds to set up window ${windowId}"
			sleep ${val} &
			wait ${!} || :
		}
		break
	done < <(grep -se "^rule${rule}_set_delay=" \
	< <(set))

	GetDesktopStatus

	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		case "${prop}" in
		rule${rule}_set_position)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Moving to ${val}"
			xdotool windowmove --sync "${windowId}" ${val} || :
			;;
		rule${rule}_set_size)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting size to ${val}"
			xdotool windowsize --sync "${windowId}" ${val} || :
			;;
		rule${rule}_set_minimized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				[ -z "${Debug}" ] || \
					_log "window ${windowId}: Minimizing"
				xdotool windowminimize --sync "${windowId}" || :
			else
				[ -z "${Debug}" ] || \
					_log "window ${windowId}: Un-minimizing"
				wmctrl -i -r "${windowId}" -b add,maximized_horz,maximized_vert || :
				sleep 0.1
				wmctrl -i -r "${windowId}" -b remove,maximized_horz,maximized_vert || :
			fi
			;;
		rule${rule}_set_maximized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_MAXIMIZED_HORZ' \
				'_NET_WM_STATE_MAXIMIZED_VERT' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing"
					wmctrl -i -r "${windowId}" -b add,maximized_horz,maximized_vert || :
				}
			else
				! IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_MAXIMIZED_HORZ' \
				'_NET_WM_STATE_MAXIMIZED_VERT' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing"
					wmctrl -i -r "${windowId}" -b remove,maximized_horz,maximized_vert || :
				}
			fi
			;;
		rule${rule}_set_maximized_horizontally)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_MAXIMIZED_HORZ' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing horizontally"
					wmctrl -i -r "${windowId}" -b add,maximized_horz || :
				}
			else
				! IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_MAXIMIZED_HORZ' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing horizontally"
					wmctrl -i -r "${windowId}" -b remove,maximized_horz || :
				}
			fi
			;;
		rule${rule}_set_maximized_vertically)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_MAXIMIZED_VERT' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing vertically"
					wmctrl -i -r "${windowId}" -b add,maximized_vert || :
				}
			else
				! IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_MAXIMIZED_VERT' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing vertically "
					wmctrl -i -r "${windowId}" -b remove,maximized_vert || :
				}
			fi
			;;
		rule${rule}_set_fullscreen)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_FULLSCREEN' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Setting fullscreen"
					wmctrl -i -r "${windowId}" -b add,fullscreen || :
				}
			else
				! IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_FULLSCREEN' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling fullscreen"
					wmctrl -i -r "${windowId}" -b remove,fullscreen || :
				}
			fi
			;;
		rule${rule}_set_focus)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting focus"
			xdotool windowactivate --sync "${windowId}" || :
			;;
		rule${rule}_set_above)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_BELOW' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling below"
					wmctrl -i -r "${windowId}" -b remove,below || :
				}
				IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_ABOVE' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Setting above"
					wmctrl -i -r "${windowId}" -b add,above || :
				}
			else
				! IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_ABOVE' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling above"
					wmctrl -i -r "${windowId}" -b remove,above || :
				}
			fi
			;;
		rule${rule}_set_below)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_ABOVE' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling above"
					wmctrl -i -r "${windowId}" -b remove,above || :
				}
				IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_BELOW' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Setting below"
					wmctrl -i -r "${windowId}" -b add,below || :
				}
			else
				! IsWindowWMStateActive "${windowId}" \
				'_NET_WM_STATE_BELOW' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling below"
					wmctrl -i -r "${windowId}" -b remove,below || :
				}
			fi
			;;
		rule${rule}_set_desktop)
			GetWindowDesktop
			if [ ${val} -lt ${desktops} -a \
			${val} -ne ${windowDesktop} ]; then
				[ -z "${Debug}" ] || \
					_log "window ${windowId}: Setting desktop to ${val}"
				xdotool set_desktop_for_window "${windowId}" ${val} || :
			fi
			;;
		rule${rule}_set_active_desktop)
			if [ ${val} -lt ${desktops} -a \
			{val} -ne ${desktopCurrent} ]; then
				[ -z "${Debug}" ] || \
					_log "window ${windowId}: Setting active desktop to ${val}"
				xdotool set_desktop ${val} || :
			fi
			;;
		rule${rule}_set_closed)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Closing window"
			xdotool windowclose "${windowId}" || :
			;;
		rule${rule}_set_killed)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Killing window"
			xdotool windowkill "${windowId}" || :
			;;
		rule${rule}_set_delay)
			:
			;;
		*)
			LogPrio="err" _log "WindowSetup: Invalid property ${prop}='${val}'"
			;;
		esac
	done < <(sort \
	< <(grep -se "^rule${rule}_set_" \
	< <(set)))
	return ${OK}
}

WindowNew() {
	local windowId="${1}" \
		window_title \
		window_type \
		window_application \
		window_class \
		window_role \
		window_desktop \
		window_desktop_size \
		window_desktop_workarea \
		window_is_maximized \
		window_is_maximized_horz \
		window_is_maximized_vert \
		rule

	window_title="$(GetWindowTitle "${windowId}")" || \
		return ${OK}
	window_type="$(GetWindowType "${windowId}")" || \
		return ${OK}
	window_application="$(GetWindowApplication "${windowId}")" || \
		return ${OK}
	window_class="$(GetWindowClass "${windowId}")" || \
		return ${OK}
	window_role="$(GetWindowRole "${windowId}")" || :
	window_desktop="$(GetWindowDesktop "${windowId}")" || \
		return ${OK}
	window_desktop_size="$(GetDesktopSize)" || \
		return ${OK}
	window_desktop_workarea="$(GetDesktopWorkarea)" || \
		return ${OK}
	window_is_maximized="$(GetWindowIsMaximized "${windowId}")" || \
		return ${OK}
	window_is_maximized_horz="$(GetWindowIsMaximizedHorz "${windowId}")" || \
		return ${OK}
	window_is_maximized_vert="$(GetWindowIsMaximizedVert "${windowId}")" || \
		return ${OK}

	# checking properties of this window
	# we'll set up only the first rule that matches
	rule=${NONE}
	while [ $((rule++)) -lt ${Rules} ]; do
		local rc="${AFFIRMATIVE}" prop val
		[ -z "${Debug}" ] || \
			_log "window ${windowId}: checking rule num. ${rule}"
		while [ -n "${rc}" ] && \
		IFS="=" read -r prop val; do
			val="$(_unquote "${val}")"
			case "${prop}" in
			rule${rule}_check_title)
				if [ "${val}" = "${window_title}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_title \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_title \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_type)
				if grep -qs -iwF "${window_type}" <<< "${val}" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_type \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_type \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_application)
				if grep -qs -iF "${window_application}" <<< "${val}" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_application \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_application \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_class)
				if grep -qs -iwF "${window_class}" <<< "${val}" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_class \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_class \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_role)
				if grep -qs -iwF "${window_role}" <<< "${val}"; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_role \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_role \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_desktop)
				if [ "${val}" = "${window_desktop}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_desktop \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_desktop \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_desktop_size)
				if [ "${val}" = "${window_desktop_size}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_desktop_size \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_desktop_size \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_desktop_workarea)
				if [ "${val}" = "${window_desktop_workarea}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_desktop_workarea \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_desktop_workarea \"${val}\""
					rc=""
				fi
				;;
			*)
				rc=""
				;;
			esac
		done < <(sort \
		< <(grep -se "^rule${rule}_check_" \
		< <(set)))

		if [ -n "${rc}" ]; then
			((WindowSetup "${windowId}" "${rule}")& )
			return ${OK}
		fi
	done
	[ -z "${Debug}" ] || \
		_log "window ${windowId}: doesn't match any rule"
	return ${OK}
}

WindowsUpdate() {
	local windowId
	[ -z "${Debug}" ] || \
		_log "current window count ${#}"
	for windowId in $(grep -svwF "$(printf '%s\n' ${WindowIds})" \
	< <(printf '%s\n' "${@}")); do
		! grep -qswEe "_NET_WM_WINDOW_TYPE_DESKTOP|_NET_WM_WINDOW_TYPE_DOCK" \
		< <(GetWindowProp "${windowId}" "_NET_WM_WINDOW_TYPE") || \
			continue
		[ -z "${Debug}" ] || \
			while read -r line; do
				if [[ $(cut -f 1 -s -d ' ' <<< "${line}") -eq ${windowId} ]]; then
					_log "new window ${windowId}: $(cut -f 2- -s -d ' ' <<< "${line}")"
					break
				fi
			done < <(wmctrl -l -x)
		WindowNew "${windowId}" || :
	done
	[ -z "${Debug}" ] || \
		for windowId in $(grep -svwF "$(printf '%s\n' "${@}")" \
		< <(printf '%s\n' ${WindowIds})); do
			_log "window ${windowId}: has been closed"
		done
	WindowIds="${@}"
	return ${OK}
}

Main() {
	# constants
	local XROOT t=0
	while ! XROOT="$(xprop -root _NET_SUPPORTING_WM_CHECK | \
	awk '$NF ~ "^0x[0-9A-Fa-f]+$" {print $NF; rc=-1; exit}
	END{exit rc+1}')" && \
	[ $((t++)) -lt 5 ]; do
		sleep 1
	done 2> /dev/null
	[ -n "${XROOT}" ] || \
		exit ${ERR}
	readonly NAME="$(basename "${0}")" \
		APPNAME="setnewwinprops" \
		XROOT
	readonly LOGFILE="/tmp/${APPNAME}/${USER}/${XROOT}" \
		PIDFILE="/tmp/${APPNAME}/${USER}/${XROOT}.pid" \
		PIPE="/tmp/${APPNAME}/${USER}/${XROOT}.pipe" \
		PID="${$}"
	# internal variables, daemon scope
	local Rules Debug LogPrio txt \
		WindowIds="" pidsChildren

	trap '_exit' EXIT
	trap 'exit' INT
	trap 'echo reload >> "${PIPE}"' HUP

	mkdir -p -m 0777 "/tmp/${APPNAME}"
	mkdir -p "/tmp/${APPNAME}/${USER}"
	rm -f "${LOGFILE}"*

	echo "${PID}" > "${PIDFILE}"

	[ -e "${PIPE}" ] || \
		mkfifo "${PIPE}"

	! grep -qswF 'xtrace' <<<"${@}" || {
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {bash_xtracefd}> "${LOGFILE}.xtrace"
		BASH_XTRACEFD=${bash_xtracefd}
		set -o xtrace
	}
	exec > "${LOGFILE}" 2>&1

	_log "Start"
	LoadConfig "${@}"

	(xprop -root -spy "_NET_CLIENT_LIST" >> "${PIPE}" || \
	kill -INT ${PID})&

	while :; do
		if read -r txt < "${PIPE}"; then
			case "${txt}" in
			_NET_CLIENT_LIST*)
				WindowsUpdate $(cut -f 2- -s -d '#' <<< "${txt}" | \
					tr -s ' ,' ' ')
				;;
			reload)
				LoadConfig "${@}"
				;;
			esac
		elif ! xprop -root "_NET_SUPPORTING_WM_CHECK"; then
			exit ${OK}
		fi
	done
}

set -o errexit -o nounset -o pipefail +o noglob +o noclobber
case "${1:-}" in
start)
	shift
	Main "${@}"
	;;
*)
	echo "Wrong arguments" >&2
	exit 1
	;;
esac
