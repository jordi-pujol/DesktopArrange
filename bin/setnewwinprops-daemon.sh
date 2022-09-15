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

WindowSet() {
	local id="${1}" \
		window="${2}" \
		delay="${3:-}" \
		desktopCurrent desktops x y \
		desktopWidth desktopHeight \
		windowWidth windowHeight windowX windowY windowDesktop \
		prop val

	if [ -n "${delay}" ]; then
		sleep ${delay} &
		wait ${!} || :
	fi

	DesktopStatus

	#$ xprop -id 0x1e00009 | grep  _NET_WM_ALLOWED_ACTIONS
	# _NET_WM_ALLOWED_ACTIONS(ATOM) = _NET_WM_ACTION_CLOSE, _NET_WM_ACTION_ABOVE, 
	# _NET_WM_ACTION_BELOW, _NET_WM_ACTION_MINIMIZE, _NET_WM_ACTION_CHANGE_DESKTOP, 
	# _NET_WM_ACTION_STICK
	#
	# wmctrl -i -r "${id}" -b [add/remove],fullscreen,above,...
	# modal, sticky, maximized_vert, maximized_horz, shaded, skip_taskbar,
	# skip_pager, hidden, fullscreen, above and below

	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		case "${prop}" in
			window${window}_set_position)
				xdotool windowmove --sync "${id}" ${val}
			;;
			window${window}_set_size)
				xdotool windowsize --sync "${id}" ${val}
			;;
			window${window}_set_minimized)
				xdotool windowminimize --sync "${id}"
			;;
			window${window}_set_maximized)
				case "${val}" in
				y*|true|on|1|enable*)
					wmctrl -i -r "${id}" -b add,maximized_horz,maximized_vert
				;;
				*)
					wmctrl -i -r "${id}" -b remove,maximized_horz,maximized_vert
				;;
				esac
				#xdotool windowmove --sync "${id}" 0 0
				#xdotool windowsize --sync "${id}" "99%" "97%"
			;;
			window${window}_set_maximized_horizontally)
				case "${val}" in
				y*|true|on|1|enable*)
					wmctrl -i -r "${id}" -b add,maximized_horz
				;;
				*)
					wmctrl -i -r "${id}" -b remove,maximized_horz
				;;
				esac
				#xdotool windowmove --sync "${id}" 0 "y"
				#xdotool windowsize --sync "${id}" "99%" "y"
			;;
			window${window}_set_maximized_vertically)
				case "${val}" in
				y*|true|on|1|enable*)
					wmctrl -i -r "${id}" -b add,maximized_vert
				;;
				*)
					wmctrl -i -r "${id}" -b remove,maximized_vert
				;;
				esac
				#xdotool windowmove --sync "${id}" "x" 0
				#xdotool windowsize --sync "${id}" "x" "97%"
			;;
			window${window}_set_fullscreen)
				case "${val}" in
				y*|true|on|1|enable*)
					wmctrl -i -r "${id}" -b add,fullscreen
				;;
				*)
					wmctrl -i -r "${id}" -b remove,fullscreen
				;;
				esac
			;;
			window${window}_set_above)
				case "${val}" in
				y*|true|on|1|enable*)
					wmctrl -i -r "${id}" -b remove,below
					wmctrl -i -r "${id}" -b add,above
				;;
				*)
					wmctrl -i -r "${id}" -b remove,above
					wmctrl -i -r "${id}" -b add,below
				;;
				esac
				#xdotool windowraise "${id}"
			;;
			window${window}_set_focus)
				WindowStatus
				[ ${windowDesktop} -eq ${desktopCurrent} ] || \
					xdotool set_desktop "${windowDesktop}"
				xdotool windowfocus --sync "${id}"
				;;
			window${window}_set_desktop)
				WindowStatus
				if [ ${val} -lt ${desktops} -a \
				${val} -ne ${windowDesktop} ]; then
					xdotool set_desktop_for_window "${id}" ${val}
				fi
			;;
			window${window}_set_active_desktop)
				if [ ${val} -lt ${desktops} -a \
				{val} -ne ${desktopCurrent} ]; then
					xdotool set_desktop ${val}
				fi
			;;
			window${window}_set_killed)
				xdotool windowclose "${id}"
			;;
		esac
	done < <(set | grep -se "^window${window}_set_" | sort)
	return ${OK}
}

WindowNew() {
	local id="${1}" \
		window_get_title \
		window_get_type \
		window_get_application \
		window_get_class \
		window_get_role \
		window delay=""

	window_get_title="$(GetTitle "${id}")"
	window_get_type="$(GetType "${id}")"
	window_get_application="$(GetApplication "${id}")"
	window_get_class="$(GetClass "${id}")"
	window_get_role="$(GetRole "${id}")"

	window=${NONE}
	while [ $((window++)) -lt ${Windows} ]; do
		local rc="y" prop val
		while [ -n "${rc}" ] && \
		IFS="=" read -r prop val; do
			val="$(_unquote "${val}")"
			case "${prop}" in
				window${window}_get_title)
					[ "${val}" = "${window_get_title}" ] || \
						rc=""
				;;
				window${window}_get_type)
					grep -qs -iF "${window_get_type}" <<< "${val}" || \
						rc=""
				;;
				window${window}_get_application)
					[ "${val}" = "${window_get_application}" ] || \
						rc=""
				;;
				window${window}_get_class)
					grep -qs -iF "${window_get_class}" <<< "${val}" || \
						rc=""
				;;
				window${window}_get_role)
					grep -qs -iF "${window_get_role}" <<< "${val}" || \
						rc=""
				;;
				window${window}_get_delay)
					delay="${val}"
				;;
				*)
					rc=""
				;;
			esac
		done < <(set | grep -se "^window${window}_get_" | sort)
		if [ -n "${rc}" ]; then
			# process only the first match
			((WindowSet "${id}" "${window}" ${delay})& )
			return ${OK}
		fi
	done
	# get out when no window matches
	return ${OK}
}

WindowsUpdate() {
	local id newIds
	if newIds="$(grep -svwF "$(printf '%s\n' ${Ids})" \
	< <(printf '%s\n' "${@}"))"; then
		for id in ${newIds}; do
			WindowNew "${id}" || :
		done
		Ids="${@}"
	fi
	return ${OK}
}

Main() {
	# constants
	readonly NAME \
		TAB=$'\t' OK=0 ERR=1 NONE=0 \
		XROOT="$(xprop -root _NET_SUPPORTING_WM_CHECK | \
			awk '{print $NF; exit}')"
	readonly LOGFILE="/tmp/${APPNAME}/${USER}/${XROOT}" \
		PIDFILE="/tmp/${APPNAME}/${USER}/${XROOT}.pid"
		PIPE="/tmp/${APPNAME}/${USER}/${XROOT}.pipe"
	# internal variables, daemon scope
	local Windows Debug LogPrio txt \
		Ids pidsChildren pid \
		LogOutput="/dev/null"

	trap '_exit' EXIT
	trap 'exit' INT
	trap 'echo reload >> "${PIPE}"' HUP

	mkdir -p -m 0777 "/tmp/${APPNAME}"
	mkdir -p -m 0755 "/tmp/${APPNAME}/${USER}"
	echo "${$}" > "${PIDFILE}"
	[ -e "${PIPE}" ] || \
		mkfifo "${PIPE}"
	exec > "${LOGFILE}" 2>&1

	_log "Start"
	# initialize Ids with sticky window ids
	Ids="$(awk '$2 == -1 {printf $1 " "}' < <(wmctrl -l))"
	LoadConfig "${@}"

	((exec xprop -root -spy "_NET_CLIENT_LIST_STACKING" >> "${PIPE}")& )
	while :; do
		if read -r txt < "${PIPE}"; then
			case "${txt}" in
			_NET_CLIENT_LIST_STACKING*)
				WindowsUpdate $(cut -f 2- -s -d '#' <<< "${txt}" | \
					tr -s ' ,' ' ')
				;;
			reload)
				LoadConfig "${@}"
				;;
			esac
		fi
	done
}

set -o errexit -o nounset -o pipefail +o noglob +o noclobber
NAME="$(basename "${0}")"
APPNAME="SetNewWinProps"
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
