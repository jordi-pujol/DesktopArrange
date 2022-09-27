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

. /usr/lib/setnewwinprops/setnewwinprops.sh

_exit() {
	local pidsChildren
	trap - EXIT INT HUP
	set +o xtrace
	LogPrio="warn" _log "Exit"
	rm -f "${PIPE}" "${PIDFILE}"
	pidsChildren=""; _ps_children
	[ -z "${pidsChildren}" ] || \
		kill -s TERM ${pidsChildren} 2> /dev/null || :
	[ -n "${Debug}" ] || \
		rm -f "${LOGFILE}"*
	wait || :
}

CheckWindowExists() {
	local windowId="${1}"
	WindowExists ${windowId} || {
		_log "window ${windowId}: can't set up this window, has been closed"
		return ${ERR}
	}
}

CmdWaitFocus() {
	local windowId="${1}"
	echo "xdotool behave ${windowId} focus" \
		"exec /usr/bin/SetNewWinProps-waitfocus.sh"
}

WindowSetup() {
	local windowId="${1}" \
		rule="${2}" \
		desktopCurrent desktops \
		desktopWidth desktopHeight \
		windowWidth windowHeight windowX windowY windowScreen \
		prop val

	[ -z "${Debug}" ] || \
		_log "window ${windowId}:" \
		"Setting up using rule num. ${rule}"

	GetDesktopStatus

	eval val=\"\${rule${rule}_set_desktop:-}\"
	if [ -n "${val}" ]; then
		if [ ${val} -lt ${desktops} ]; then
			if [ ${val} -ne $(GetWindowDesktop "${windowId}") ]; then
				[ -z "${Debug}" ] || \
					_log "window ${windowId}: Moving window to desktop to ${val}"
				xdotool set_desktop_for_window ${windowId} ${val} || {
					! CheckWindowExists ${windowId} || \
						LogPrio="err" _log "window ${windowId}:" \
						"Error moving window to desktop to ${val}"
					return ${OK}
				}
			fi
		else
			LogPrio="err" _log "window ${windowId}:" \
				"Can't move window to invalid desktop ${val}"
		fi
	fi

	eval val=\"\${rule${rule}_set_delay:-}\"
	if [ ${val} -gt ${NONE} ]; then
		[ -z "${Debug}" ] || \
			_log "window ${windowId}:" \
			"Waiting ${val} seconds to set up"
		while [ $((val--)) -ge ${NONE} ]; do
			sleep 1
			CheckWindowExists ${windowId} || \
				return ${OK}
		done
	fi

	GetDesktopStatus

	eval val=\"\${rule${rule}_set_active_desktop:-}\"
	if [ -n "${val}" ]; then
		if [ ${val} -lt ${desktops} ]; then
			if [ ${val} -ne ${desktopCurrent} ]; then
				[ -z "${Debug}" ] || \
					_log "window ${windowId}: Setting up active desktop ${val}"
				xdotool set_desktop ${val} || {
					LogPrio="err" _log "window ${windowId}:" \
						"Error setting up active desktop ${val}"
					return ${OK}
				}
			fi
		else
			LogPrio="err" _log "window ${windowId}:" \
				"Can't set invalid active desktop ${val}"
		fi
	fi

	if [[ $(xdotool getactivewindow) -ne ${windowId} ]]; then
		eval val=\"\${rule${rule}_set_focus:-}\"
		if [ -n "${val}" ]; then
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting up focus"
			xdotool windowactivate --sync ${windowId} || {
				CheckWindowExists ${windowId} || :
				return ${OK}
			}
		else
			[ -z "${Debug}" ] || \
				_log "window ${windowId}:" \
				"Waiting to get focus"
			(export windowId LOGFILE Debug BASH_XTRACEFD
			$(CmdWaitFocus ${windowId})) &
			wait ${!} || :
			CheckWindowExists ${windowId} || \
				return ${OK}
		fi
	fi

	GetDesktopStatus

	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		CheckWindowExists ${windowId} || \
			return ${OK}
		case "${prop}" in
		rule${rule}_set_position)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Moving to ${val}"
			xdotool windowmove --sync ${windowId} ${val} || {
				! CheckWindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error moving to ${val}"
				return ${OK}
			}
			;;
		rule${rule}_set_size)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting up size to ${val}"
			xdotool windowsize --sync ${windowId} ${val} || {
				! CheckWindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error setting up size to ${val}"
				return ${OK}
			}
			;;
		rule${rule}_set_minimized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				[ -z "${Debug}" ] || \
					_log "window ${windowId}: Minimizing"
				xdotool windowminimize --sync ${windowId} || {
				! CheckWindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error minimizing"
				return ${OK}
			}
			else
				[ -z "${Debug}" ] || \
					_log "window ${windowId}: Un-minimizing"
				wmctrl -i -r ${windowId} -b add,maximized_horz,maximized_vert || {
					! CheckWindowExists ${windowId} || \
						LogPrio="err" _log "window ${windowId}:" \
						"Error un-minimizing"
					return ${OK}
				}
				sleep 0.1
				wmctrl -i -r ${windowId} -b remove,maximized_horz,maximized_vert || {
					! CheckWindowExists ${windowId} || \
						LogPrio="err" _log "window ${windowId}:" \
						"Error un-minimizing"
					return ${OK}
				}
			fi
			;;
		rule${rule}_set_maximized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_MAXIMIZED_HORZ' \
				'_NET_WM_STATE_MAXIMIZED_VERT' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing"
					wmctrl -i -r ${windowId} -b add,maximized_horz,maximized_vert || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error maximizing"
						return ${OK}
					}
				}
			else
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_MAXIMIZED_HORZ' \
				'_NET_WM_STATE_MAXIMIZED_VERT' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing"
					wmctrl -i -r ${windowId} -b remove,maximized_horz,maximized_vert || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-maximizing"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_maximized_horizontally)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_MAXIMIZED_HORZ' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing horizontally"
					wmctrl -i -r ${windowId} -b add,maximized_horz || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error maximizing horizontally"
						return ${OK}
					}
				}
			else
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_MAXIMIZED_HORZ' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing horizontally"
					wmctrl -i -r ${windowId} -b remove,maximized_horz || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-maximizing horizontally"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_maximized_vertically)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_MAXIMIZED_VERT' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing vertically"
					wmctrl -i -r ${windowId} -b add,maximized_vert || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error maximizing vertically"
						return ${OK}
					}
				}
			else
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_MAXIMIZED_VERT' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing vertically "
					wmctrl -i -r ${windowId} -b remove,maximized_vert || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-maximizing vertically"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_shaded)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_SHADED' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Shading"
					wmctrl -i -r ${windowId} -b add,shade || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error shading"
						return ${OK}
					}
				}
			else
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_SHADED' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-shading"
					wmctrl -i -r ${windowId} -b remove,shade || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-shading"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_sticky)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_STICKY' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Sticking"
					wmctrl -i -r ${windowId} -b add,sticky || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error sticking"
						return ${OK}
					}
				}
			else
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_STICKY' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-sticking"
					wmctrl -i -r ${windowId} -b remove,sticky || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-sticking"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_fullscreen)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_FULLSCREEN' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Enabling fullscreen"
					wmctrl -i -r ${windowId} -b add,fullscreen || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error enabling fullscreen"
						return ${OK}
					}
				}
			else
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_FULLSCREEN' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling fullscreen"
					wmctrl -i -r ${windowId} -b remove,fullscreen || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error disabling fullscreen"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_above)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_BELOW' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling below"
					wmctrl -i -r ${windowId} -b remove,below || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error disabling below"
						return ${OK}
					}
				}
				IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_ABOVE' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Enabling above"
					wmctrl -i -r ${windowId} -b add,above || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error enabling above"
						return ${OK}
					}
				}
			else
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_ABOVE' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling above"
					wmctrl -i -r ${windowId} -b remove,above || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error disabling above"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_below)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_ABOVE' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling above"
					wmctrl -i -r ${windowId} -b remove,above || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error disabling above"
						return ${OK}
					}
				}
				IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_BELOW' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Enabling below"
					wmctrl -i -r ${windowId} -b add,below || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error enabling below"
						return ${OK}
					}
				}
			else
				! IsWindowWMStateActive ${windowId} \
				'_NET_WM_STATE_BELOW' || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling below"
					wmctrl -i -r ${windowId} -b remove,below || {
						! CheckWindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error disabling below"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_closed)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Closing window"
			xdotool windowclose ${windowId} || {
				! CheckWindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error closing window"
				return ${OK}
			}
			;;
		rule${rule}_set_killed)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Killing window"
			xdotool windowkill ${windowId} || {
				! CheckWindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error killing window"
				return ${OK}
			}
			;;
		rule${rule}_set_delay | \
		rule${rule}_set_desktop | \
		rule${rule}_set_focus | \
		rule${rule}_set_active_desktop)
			:
			;;
		*)
			LogPrio="err" _log "window ${windowId}:" \
				"WindowSetup: Invalid property ${prop}='${val}'"
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
		window_state \
		window_type \
		window_app_name \
		window_application \
		window_class \
		window_role \
		window_desktop \
		window_desktop_size \
		window_desktop_workarea \
		window_is_maximized \
		window_is_maximized_horz \
		window_is_maximized_vert \
		window_is_shaded \
		window_is_sticky \
		rule

	window_title="$(GetWindowTitle "${windowId}")" || \
		return ${OK}
	window_state="$(GetWindowState "${windowId}")" || \
		return ${OK}
	window_type="$(GetWindowType "${windowId}")" || \
		return ${OK}
	window_app_name="$(GetWindowAppName "${windowId}")" || \
		return ${OK}
	window_application="$(GetWindowApplication "${windowId}" 2> /dev/null)" || \
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
	window_is_shaded="$(GetWindowIsShaded "${windowId}")" || \
		return ${OK}
	window_is_sticky="$(GetWindowIsSticky "${windowId}")" || \
		return ${OK}

	[ -z "${Debug}" ] || {
		printf "%s='%s'\n" \
			"New window id" ${windowId} \
			"window_title" "${window_title}" \
			"window_state" "${window_state}" \
			"window_type" "${window_type}" \
			"window_app_name" "${window_app_name}" \
			"window_application" "${window_application}" \
			"window_class" "${window_class}" \
			"window_desktop" "${window_desktop}" \
			"window_desktop_size" "${window_desktop_size}" \
			"window_desktop_workarea" "${window_desktop_workarea}" \
			"window_is_maximized" "${window_is_maximized}" \
			"window_is_maximized_horz" "${window_is_maximized_horz}" \
			"window_is_maximized_vert" "${window_is_maximized_vert}" \
			"window_is_shaded" "${window_is_shaded}" \
			"window_is_sticky" "${window_is_sticky}"
		test -z "${window_role}" || \
			printf "%s='%s'\n" "window_role" "${window_role}"
				
	} >> "${LOGFILE}"

	# checking properties of this window
	# we'll set up only the first rule that matches
	rule=${NONE}
	while [ $((rule++)) -lt ${Rules} ]; do
		local rc="${AFFIRMATIVE}" prop val
		[ -z "${Debug}" ] || \
			_log "window ${windowId}: Checking rule num. ${rule}"
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
			rule${rule}_check_state)
				if [ "${val}" = "${window_state}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_state \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_state \"${val}\""
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
			rule${rule}_check_app_name)
				if [ "${val}" = "${window_app_name}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_app_name \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_app_name \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_application)
				if grep -qs -iwF "${window_application}" <<< "${val}" ; then
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
			(WindowSetup ${windowId} "${rule}") &
			return ${OK}
		fi
	done
	[ -z "${Debug}" ] || \
		_log "window ${windowId}: Doesn't match any rule"
	return ${OK}
}

WindowsUpdate() {
	local windowId window_type pids
	[ -z "${Debug}" ] || \
		_log "current window count ${#}"
	for windowId in $(grep -svwF "$(printf '%s\n' ${WindowIds})" \
	< <(printf '%s\n' "${@}")); do
		if ! window_type="$(GetWindowType ${windowId})" || \
		grep -qswF "_NET_WM_WINDOW_TYPE_DESKTOP${LF}_NET_WM_WINDOW_TYPE_DOCK" \
		<<< "${window_type}"; then
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: discarding window" \
				$([ -z "${window_type}" ] || \
				echo "of type \"$(awk -F '_' '{print $NF}' <<< "${window_type}")\"")
			continue
		fi

		WindowNew ${windowId} || :
	done

	for windowId in $(grep -svwF "$(printf '%s\n' "${@}")" \
	< <(printf '%s\n' ${WindowIds})); do
		[ -z "${Debug}" ] || \
			_log "window ${windowId}: has been closed"
		if pids="$(ps -C "$(CmdWaitFocus ${windowId})" -o pid= -o user= | \
		awk -v user="${USER}" \
		'$2 == user && $1 ~ "^[[:digit:]]+$" {printf $1 " "; rc=-1}
		END{exit rc+1}')"; then
			kill ${pids} 2> /dev/null || :
		fi
	done

	WindowIds="${@}"
	return ${OK}
}

Main() {
	# internal variables, daemon scope
	local Rules Debug LogPrio txt \
		WindowIds=""

	trap '_exit' EXIT
	trap 'exit' INT
	trap 'echo reload >> "${PIPE}"' HUP

	mkdir -p -m 0777 "/tmp/${APPNAME}"
	mkdir -p "/tmp/${APPNAME}/${USER}"
	rm -f "${LOGFILE}"*

	echo "${$}" > "${PIDFILE}"

	[ -e "${PIPE}" ] || \
		mkfifo "${PIPE}"

	! grep -qswF 'xtrace' <<< "${@}" || {
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {BASH_XTRACEFD}> "${LOGFILE}.xtrace"
		set -o xtrace
	}
	exec > "${LOGFILE}" 2>&1

	_log "Start"
	LoadConfig "${@}"

	(while xprop -root "_NET_CLIENT_LIST" > /dev/null 2>&1; do
		xprop -root -spy "_NET_CLIENT_LIST" >> "${PIPE}" || :
	done
	kill -INT ${$}) &

	while :; do
		if read -r txt < "${PIPE}"; then
			case "${txt}" in
			_NET_CLIENT_LIST*)
				WindowsUpdate $(tr -s ' ,' ' ' \
					< <(cut -f 2- -s -d '#' <<< "${txt}"))
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

# constants
readonly NAME="$(basename "${0}")" \
	APPNAME="setnewwinprops"
XROOT="$(GetXroot)" || \
	exit ${ERR}
readonly XROOT \
	LOGFILE="/tmp/${APPNAME}/${USER}/${XROOT}" \
	PIDFILE="/tmp/${APPNAME}/${USER}/${XROOT}.pid" \
	PIPE="/tmp/${APPNAME}/${USER}/${XROOT}.pipe"

case "${1:-}" in
start)
	if pid="$(AlreadyRunning)"; then
		echo "Error: ${APPNAME} is already running for this session" >&2
		exit ${ERR}
	fi
	if [ $(ps -o ppid= ${$}) -eq 1 ]; then
		shift
		echo "Info: ${APPNAME} start" >&2
		Main "${@}"
	else
		echo "Info: ${APPNAME} submit" >&2
		(("${0}" "${@}" > /dev/null 2>&1) &)
	fi
	;;
status)
	if ! pid="$(AlreadyRunning)"; then
		echo "Info: ${APPNAME} is not running for this session" >&2
		exit ${ERR}
	fi
	;;
stop)
	if ! pid="$(AlreadyRunning)"; then
		echo "Error: ${APPNAME} is not running for this session" >&2
		exit ${ERR}
	fi
	echo "Info: ${APPNAME} stop" >&2
	kill -s INT ${pid} 2> /dev/null
	;;
restart)
	exec "${0}" stop &
	wait ${!} || :
	exec "${0}" start &
	wait ${!} || exit ${?}
	;;
reload)
	if ! pid="$(AlreadyRunning)"; then
		echo "Error: ${APPNAME} is not running for this session" >&2
		exit ${ERR}
	fi
	echo "Info: ${APPNAME} reload" >&2
	kill -s HUP ${pid} 2> /dev/null
	;;
*)
	echo "Wrong action." >&2
	echo "Valid actions are: start|stop|restart|status|reload" >&2
	exit ${ERR}
	;;
esac
:
