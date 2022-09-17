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
		delay="${3:-}" \
		desktopCurrent desktops x y \
		desktopWidth desktopHeight \
		windowWidth windowHeight windowX windowY windowDesktop \
		prop val

	if [ -n "${delay}" ]; then
		sleep ${delay} &
		wait ${!} || :
	fi

	GetDesktopStatus

	#$ xprop -id 0x1e00009 | grep  _NET_WM_ALLOWED_ACTIONS
	# _NET_WM_ALLOWED_ACTIONS(ATOM) = _NET_WM_ACTION_CLOSE, _NET_WM_ACTION_ABOVE, 
	# _NET_WM_ACTION_BELOW, _NET_WM_ACTION_MINIMIZE, _NET_WM_ACTION_CHANGE_DESKTOP, 
	# _NET_WM_ACTION_STICK
	#
	# wmctrl -i -r "${windowId}" -b [add/remove],fullscreen,above,...
	# modal, sticky, maximized_vert, maximized_horz, shaded, skip_taskbar,
	# skip_pager, hidden, fullscreen, above and below

	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		case "${prop}" in
			rule${rule}_set_position)
				xdotool windowmove --sync "${windowId}" ${val} || :
			;;
			rule${rule}_set_size)
				xdotool windowsize --sync "${windowId}" ${val} || :
			;;
			rule${rule}_set_minimized)
				if [ "${val}" = "y" ]; then
					xdotool windowminimize --sync "${windowId}" || :
				else
					wmctrl -i -r "${windowId}" -b add,maximized_horz,maximized_vert || :
					sleep 0.1
					wmctrl -i -r "${windowId}" -b remove,maximized_horz,maximized_vert || :
				fi
			;;
			rule${rule}_set_maximized)
				if [ "${val}" = "y" ]; then
					wmctrl -i -r "${windowId}" -b add,maximized_horz,maximized_vert || :
				else
					wmctrl -i -r "${windowId}" -b remove,maximized_horz,maximized_vert || :
				fi
				#xdotool windowmove --sync "${windowId}" 0 0 || :
				#xdotool windowsize --sync "${windowId}" "99%" "97%" || :
			;;
			rule${rule}_set_maximized_horizontally)
				if [ "${val}" = "y" ]; then
					wmctrl -i -r "${windowId}" -b add,maximized_horz || :
				else
					wmctrl -i -r "${windowId}" -b remove,maximized_horz || :
				fi
				#xdotool windowmove --sync "${windowId}" 0 "y" || :
				#xdotool windowsize --sync "${windowId}" "99%" "y" || :
			;;
			rule${rule}_set_maximized_vertically)
				if [ "${val}" = "y" ]; then
					wmctrl -i -r "${windowId}" -b add,maximized_vert || :
				else
					wmctrl -i -r "${windowId}" -b remove,maximized_vert || :
				fi
				#xdotool windowmove --sync "${windowId}" "x" 0 || :
				#xdotool windowsize --sync "${windowId}" "x" "97%" || :
			;;
			rule${rule}_set_fullscreen)
				if [ "${val}" = "y" ]; then
					wmctrl -i -r "${windowId}" -b add,fullscreen || :
				else
					wmctrl -i -r "${windowId}" -b remove,fullscreen || :
				fi
			;;
			rule${rule}_set_focus)
				xdotool windowactivate --sync "${windowId}" || :
				;;
			rule${rule}_set_above)
				if [ "${val}" = "y" ]; then
					wmctrl -i -r "${windowId}" -b remove,below || :
					wmctrl -i -r "${windowId}" -b add,above || :
				else
					wmctrl -i -r "${windowId}" -b remove,above || :
				fi
				#xdotool windowraise "${windowId}"
			;;
			rule${rule}_set_below)
				if [ "${val}" = "y" ]; then
					wmctrl -i -r "${windowId}" -b remove,above || :
					wmctrl -i -r "${windowId}" -b add,below || :
				else
					wmctrl -i -r "${windowId}" -b remove,below || :
				fi
			;;
			rule${rule}_set_desktop)
				GetWindowGeometry
				if [ ${val} -lt ${desktops} -a \
				${val} -ne ${windowDesktop} ]; then
					xdotool set_desktop_for_window "${windowId}" ${val}
				fi
			;;
			rule${rule}_set_active_desktop)
				if [ ${val} -lt ${desktops} -a \
				{val} -ne ${desktopCurrent} ]; then
					xdotool set_desktop ${val}
				fi
			;;
			rule${rule}_set_closed)
				xdotool windowclose "${windowId}"
			;;
			rule${rule}_set_killed)
				xdotool windowkill "${windowId}"
			;;
		esac
	done < <(set | grep -se "^rule${rule}_set_" | sort)
	return ${OK}
}

WindowNew() {
	local windowId="${1}" \
		window_title \
		window_type \
		window_application \
		window_class \
		window_role \
		window_desktop_size \
		window_desktop_workarea \
		rule delay=""
		#window_is_maximized \
		#window_is_maximized_horz \
		#window_is_maximized_vert \
		#window_desktop

	window_title="$(GetWindowTitle "${windowId}")" || \
		return ${OK}
	window_type="$(GetWindowType "${windowId}")" || \
		return ${OK}
	window_application="$(GetWindowApplication "${windowId}")" || \
		return ${OK}
	window_class="$(GetWindowClass "${windowId}")" || \
		return ${OK}
	window_role="$(GetWindowRole "${windowId}")" || \
		return ${OK}
	window_desktop_size="$(GetDesktopSize)" || \
		return ${OK}
	window_desktop_workarea="$(GetDesktopWorkarea)" || \
		return ${OK}
	#window_is_maximized="$(GetWindowIsMaximized "${windowId}")" || \
	#	return ${OK}
	#window_is_maximized_horz="$(GetWindowIsMaximizedHorz "${windowId}")" || \
	#	return ${OK}
	#window_is_maximized_vert="$(GetWindowIsMaximizedVert "${windowId}")" || \
	#	return ${OK}
	#window_desktop="$(GetWindowDesktop "${windowId}")" || \
	#	return ${OK}

	# We'll set up only the first rule that match this window
	rule=${NONE}
	while [ $((rule++)) -lt ${Rules} ]; do
		local rc="y" prop val
		while [ -n "${rc}" ] && \
		IFS="=" read -r prop val; do
			val="$(_unquote "${val}")"
			case "${prop}" in
				rule${rule}_check_title)
					[ "${val}" = "${window_title}" ] || \
						rc=""
				;;
				rule${rule}_check_type)
					grep -qs -iwF "${window_type}" <<< "${val}" || \
						rc=""
				;;
				rule${rule}_check_application)
					grep -qs -iF "${window_application}" <<< "${val}" || \
						rc=""
				;;
				rule${rule}_check_class)
					grep -qs -iwF "${window_class}" <<< "${val}" || \
						rc=""
				;;
				rule${rule}_check_role)
					grep -qs -iwF "${window_role}" <<< "${val}" || \
						rc=""
				;;
				rule${rule}_check_desktop_size)
					[ "${val}" = "${window_desktop_size}" ] || \
						rc=""
				;;
				rule${rule}_check_desktop_workarea)
					[ "${val}" = "${window_desktop_workarea}" ] || \
						rc=""
				;;
				rule${rule}_check_delay)
					delay="${val}"
				;;
				*)
					rc=""
				;;
			esac
		done < <(set | grep -se "^rule${rule}_check_" | sort)
		if [ -n "${rc}" ]; then
			((WindowSetup "${windowId}" "${rule}" ${delay})& )
			return ${OK}
		fi
	done
	# get out when any rule doesn't match
	return ${OK}
}

WindowsUpdate() {
	local windowId
	for windowId in $(grep -svwF "$(printf '%s\n' ${WindowIds})" \
	< <(printf '%s\n' "${@}")); do
		WindowNew "${windowId}" || :
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
	done
	[ -n "${XROOT}" ] || \
		exit ${ERR}
	readonly NAME="$(basename "${0}")" \
		APPNAME="setnewwinprops" \
		XROOT \
		LOGFILE="/tmp/${APPNAME}/${USER}/${XROOT}" \
		PIDFILE="/tmp/${APPNAME}/${USER}/${XROOT}.pid" \
		PIPE="/tmp/${APPNAME}/${USER}/${XROOT}.pipe"
	# internal variables, daemon scope
	local Rules Debug LogPrio txt \
		WindowIds pidsChildren pid

	trap '_exit' EXIT
	trap 'exit' INT
	trap 'echo reload >> "${PIPE}"' HUP

	mkdir -p -m 0777 "/tmp/${APPNAME}"
	mkdir -p "/tmp/${APPNAME}/${USER}"
	rm -f "${LOGFILE}"*

	echo "${$}" > "${PIDFILE}"

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
	# initialize WindowIds with ids of current sticky windows
	WindowIds="$(awk '$2 == -1 {printf $1 " "}' < <(wmctrl -l))"
	LoadConfig "${@}"

	((exec xprop -root -spy "_NET_CLIENT_LIST" >> "${PIPE}")& )
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
		else
			xprop -root "_NET_SUPPORTING_WM_CHECK" || \
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
