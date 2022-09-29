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

CmdWaitFocus() {
	local windowId="${1}"
	echo "xdotool behave ${windowId} focus" \
		"exec --sync /usr/bin/SetNewWinProps-waitfocus.sh"
}

WindowSetDesktop() {
	local windowId="${1}" \
		rule="${2}" \
		val
	eval val=\"\${rule${rule}_set_desktop:-}\"
	[ -n "${val}" ] || \
		return ${OK}
	if [ ${val} -lt ${desktopsCount} ]; then
		local c=0
		if [ ${val} -ne $(WindowDesktop ${windowId}) ]; then
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Moving window to desktop ${val}"
			xdotool set_desktop_for_window ${windowId} ${val} || {
				! WindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error moving window to desktop ${val}"
				return ${OK}
			}
			[ ${val} -eq $(WindowDesktop ${windowId}) ] || {
				[ $((c++)) -lt 5 ] && \
					sleep 1 || \
					break
			}
		fi
	else
		LogPrio="err" _log "window ${windowId}:" \
			"Can't move window to invalid desktop ${val}"
		return ${OK}
	fi
}

WindowWaitFocus() {
	local windowId="${1}" \
		rule="${2}" \
		mustGetFocus="${3}" \
		val
	if [[ $(WindowActive) -ne ${windowId} ]]; then
		WindowSetDesktop ${windowId} ${rule}
		eval val=\"\${rule${rule}_set_focus:-}\"
		if [ -n "${val}" -o -n "${mustGetFocus}" ]; then
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting up focus"
			xdotool windowactivate --sync ${windowId} || {
				WindowExists ${windowId} || :
				return ${OK}
			}
		else
			[ -z "${Debug}" ] || \
				_log "window ${windowId}:" \
				"Waiting to get focus"
			(export windowId LOGFILE Debug BASH_XTRACEFD
			$(CmdWaitFocus ${windowId})) &
			wait ${!} || :
			WindowExists ${windowId} || \
				return ${OK}
		fi
	fi
}

WindowSetupRule() {
	local windowId="${1}" \
		rule="${2}" \
		desktopWidth desktopHeight desktopCurrent desktopsCount \
		windowWidth windowHeight windowX windowY windowScreen \
		prop val mustGetFocus
	[ -z "${Debug}" ] || \
		_log "window ${windowId}:" \
		"Setting up using rule num. ${rule}"

	eval val=\"\${rule${rule}_set_ignore:-}\"
	if [ -n "${val}" ]; then
		[ -z "${Debug}" ] || \
			_log "window ${windowId}:" \
			"Ignored"
		return ${OK}
	fi

	DesktopStatus

	WindowSetDesktop ${windowId} ${rule}

	eval val=\"\${rule${rule}_set_delay:-}\"
	[ -z "${val}" ] || \
		if [ ${val} -gt ${NONE} ]; then
			[ -z "${Debug}" ] || \
				_log "window ${windowId}:" \
				"Waiting ${val} seconds to set up"
			while [ $((val--)) -ge ${NONE} ]; do
				sleep 1
				WindowExists ${windowId} || \
					return ${OK}
			done
		fi

	DesktopStatus

	eval val=\"\${rule${rule}_set_active_desktop:-}\"
	if [ -n "${val}" ]; then
		if [ ${val} -lt ${desktopsCount} ]; then
			if [ ${val} -ne ${desktopCurrent} ]; then
				[ -z "${Debug}" ] || \
					_log "window ${windowId}: Setting up active desktop ${val}"
				xdotool set_desktop ${val} || {
					LogPrio="err" _log "window ${windowId}:" \
						"Error setting up active desktop ${val}"
					return ${OK}
				}
				DesktopStatus
			fi
		else
			LogPrio="err" _log "window ${windowId}:" \
				"Can't set invalid active desktop ${val}"
			return ${OK}
		fi
	fi

	mustGetFocus=""
	while IFS="=" read -r prop val; do
		val="$(_unquote "${val}")"
		WindowExists ${windowId} || \
			return ${OK}
		WindowWaitFocus ${windowId} ${rule} ${mustGetFocus}
		DesktopStatus
		mustGetFocus="y"
		case "${prop}" in
		rule${rule}_set_position)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Moving to ${val}"
			xdotool windowmove --sync ${windowId} ${val} || {
				! WindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error moving to ${val}"
				return ${OK}
			}
			;;
		rule${rule}_set_size)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting up size to ${val}"
			xdotool windowsize --sync ${windowId} ${val} || {
				! WindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error setting up size to ${val}"
				return ${OK}
			}
			;;
		rule${rule}_set_maximized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing"
					wmctrl -i -r ${windowId} -b add,maximized_horz,maximized_vert || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error maximizing"
						return ${OK}
					}
				}
			else
				! IsWindowMaximized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing"
					wmctrl -i -r ${windowId} -b remove,maximized_horz,maximized_vert || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-maximizing"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_maximized_horizontally)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximizedHorz ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing horizontally"
					wmctrl -i -r ${windowId} -b add,maximized_horz || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error maximizing horizontally"
						return ${OK}
					}
				}
			else
				! IsWindowMaximizedHorz ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing horizontally"
					wmctrl -i -r ${windowId} -b remove,maximized_horz || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-maximizing horizontally"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_maximized_vertically)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximizedVert ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing vertically"
					wmctrl -i -r ${windowId} -b add,maximized_vert || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error maximizing vertically"
						return ${OK}
					}
				}
			else
				! IsWindowMaximizedVert ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing vertically "
					wmctrl -i -r ${windowId} -b remove,maximized_vert || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-maximizing vertically"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_fullscreen)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowFullscreen ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Enabling fullscreen"
					wmctrl -i -r ${windowId} -b add,fullscreen || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error enabling fullscreen"
						return ${OK}
					}
				}
			else
				! IsWindowFullscreen ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling fullscreen"
					wmctrl -i -r ${windowId} -b remove,fullscreen || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error disabling fullscreen"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_minimized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMinimized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Minimizing"
					xdotool windowminimize --sync ${windowId} || {
					! WindowExists ${windowId} || \
						LogPrio="err" _log "window ${windowId}:" \
						"Error minimizing"
					return ${OK}
					}
				}
			else
				! IsWindowMinimized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-minimizing"
					wmctrl -i -r ${windowId} -b add,maximized_horz,maximized_vert || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-minimizing"
						return ${OK}
					}
					sleep 0.1
					wmctrl -i -r ${windowId} -b remove,maximized_horz,maximized_vert || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-minimizing"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_shaded)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowShaded ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Shading"
					wmctrl -i -r ${windowId} -b add,shade || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error shading"
						return ${OK}
					}
				}
			else
				! IsWindowShaded ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-shading"
					wmctrl -i -r ${windowId} -b remove,shade || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-shading"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_decorated)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowDecorated ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Decorating"
					WindowTapKeys ${windowId} "alt+space" "d"
				}
			else
				! IsWindowDecorated ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-decorating"
					WindowTapKeys ${windowId} "alt+space" "d"
				}
			fi
			;;
		rule${rule}_set_sticky)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowSticky ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Sticking"
					wmctrl -i -r ${windowId} -b add,sticky || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error sticking"
						return ${OK}
					}
				}
			else
				! IsWindowSticky ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-sticking"
					wmctrl -i -r ${windowId} -b remove,sticky || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error un-sticking"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_above)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowBelow ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling below"
					wmctrl -i -r ${windowId} -b remove,below || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error disabling below"
						return ${OK}
					}
				}
				IsWindowAbove ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Enabling above"
					wmctrl -i -r ${windowId} -b add,above || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error enabling above"
						return ${OK}
					}
				}
			else
				! IsWindowAbove ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling above"
					wmctrl -i -r ${windowId} -b remove,above || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error disabling above"
						return ${OK}
					}
				}
			fi
			;;
		rule${rule}_set_below)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowAbove ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling above"
					wmctrl -i -r ${windowId} -b remove,above || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error disabling above"
						return ${OK}
					}
				}
				IsWindowBelow ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Enabling below"
					wmctrl -i -r ${windowId} -b add,below || {
						! WindowExists ${windowId} || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error enabling below"
						return ${OK}
					}
				}
			else
				! IsWindowBelow ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling below"
					wmctrl -i -r ${windowId} -b remove,below || {
						! WindowExists ${windowId} || \
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
				! WindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error closing window"
				return ${OK}
			}
			;;
		rule${rule}_set_killed)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Killing window"
			xdotool windowkill ${windowId} || {
				! WindowExists ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
					"Error killing window"
				return ${OK}
			}
			;;
		rule${rule}_set_continue | \
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

WindowSetup() {
	local windowId="${1}" \
		setuprules="${2}"

	for rule in ${setuprules}; do
		WindowSetupRule ${windowId} ${rule}
	done
	return ${OK}
}

WindowNew() {
	local windowId="${1}" \
		window_title="" \
		window_state="" \
		window_type="" \
		window_app_name="" \
		window_application="" \
		window_class="" \
		window_role="" \
		window_desktop="" \
		window_is_maximized="" \
		window_is_maximized_horz="" \
		window_is_maximized_vert="" \
		window_is_fullscreen="" \
		window_is_minimized="" \
		window_is_shaded="" \
		window_is_decorated="" \
		window_is_sticky="" \
		window_desktop_size="" \
		window_desktop_workarea="" \
		desktopWidth desktopHeight desktopCurrent desktopsCount \
		rule setuprules

	DesktopStatus

	[ -z "${Debug}" ] || {
		printf "%s='%s'\n" \
			"New window id" ${windowId} \
			"window_title" "${window_title:="$(WindowTitle ${windowId})"}" \
			"window_state" "${window_state:="$(WindowState ${windowId})"}" \
			"window_type" "${window_type:="$(WindowType ${windowId})"}" \
			"window_app_name" "${window_app_name:="$(WindowAppName ${windowId})"}" \
			"window_application" \
				"${window_application:="$(WindowApplication ${windowId} 2> /dev/null)"}" \
			"window_class" "${window_class:="$(WindowClass ${windowId})"}" \
			"window_role" "${window_role:="$(WindowRole ${windowId} || :)"}" \
			"window_desktop" "${window_desktop:="$(WindowDesktop ${windowId})"}" \
			"window_is_maximized" \
				"${window_is_maximized:="$(IsWindowMaximized ${windowId} ".")"}" \
			"window_is_maximized_horz" \
				"${window_is_maximized_horz:="$(IsWindowMaximizedHorz ${windowId} ".")"}" \
			"window_is_maximized_vert" \
				"${window_is_maximized_vert:="$(IsWindowMaximizedVert ${windowId} ".")"}" \
			"window_is_fullscreen" \
				"${window_is_fullscreen:="$(IsWindowFullscreen ${windowId} ".")"}" \
			"window_is_minimized" \
				"${window_is_minimized:="$(IsWindowMinimized ${windowId} ".")"}" \
			"window_is_shaded" \
				"${window_is_shaded:="$(IsWindowShaded ${windowId} ".")"}" \
			"window_is_decorated" \
				"${window_is_decorated:="$(IsWindowDecorated ${windowId} ".")"}" \
			"window_is_sticky" \
				"${window_is_sticky:="$(IsWindowSticky ${windowId} ".")"}" \
			"window_desktop_size" "${window_desktop_size:="$(DesktopSize)"}" \
			"window_desktop_workarea" \
				"${window_desktop_workarea:="$(DesktopWorkarea)"}" \
			"desktopsCount" "${desktopsCount}"
	} >> "${LOGFILE}"

	# checking properties of this window
	# we'll set up only the first rule that matches
	setuprules=""
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
				if [ "${val}" = "${window_title:="$(WindowTitle ${windowId})"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_title \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_title \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_state)
				if [ "${val}" = "${window_state:="$(WindowState ${windowId})"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_state \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_state \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_type)
				if grep -qs -iwF "${val}" \
				<<< "${window_type:="$(WindowType ${windowId})"}" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_type \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_type \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_app_name)
				if [ "${val}" = "${window_app_name:="$(WindowAppName ${windowId})"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_app_name \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_app_name \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_application)
				if grep -qs -iwF "${val}" \
				<<< "${window_application:="$(WindowApplication ${windowId} 2> /dev/null)"}" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_application \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_application \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_class)
				if grep -qs -iwF "${val}" \
				<<< "${window_class:="$(WindowClass ${windowId})"}" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_class \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_class \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_role)
				if grep -qs -iwF "${val}" \
				<<< "${window_role:="$(WindowRole ${windowId})"}"; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_role \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_role \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_desktop)
				if [ "${val}" = "${window_desktop:="$(WindowDesktop ${windowId})"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_desktop \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_desktop \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_is_maximized)
				if [ "${val}" = \
				"${window_is_maximized:="$(IsWindowMaximized ${windowId} ".")"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" maximized"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_is_maximized \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_is_maximized_horz)
				if [ "${val}" = \
				"${window_is_maximized_horz:="$(IsWindowMaximizedHorz ${windowId} ".")"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" maximized horizontally"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_is_maximized_horz \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_is_maximized_vert)
				if [ "${val}" = \
				"${window_is_maximized_vert:="$(IsWindowMaximizedVert ${windowId} ".")"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" maximized vertically"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_is_maximized_vert \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_is_fullscreen)
				if [ "${val}" = \
				"${window_is_fullscreen:="$(IsWindowFullscreen ${windowId} ".")"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" fullscreen"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_is_fullscreen \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_is_minimized)
				if [ "${val}" = \
				"${window_is_minimized:="$(IsWindowMinimized ${windowId} ".")"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" minimized"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_is_minimized \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_is_shaded)
				if [ "${val}" = \
				"${window_is_shaded:="$(IsWindowShaded ${windowId} ".")"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" shaded"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_is_shaded \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_is_decorated)
				if [ "${val}" = \
				"${window_is_decorated:="$(IsWindowDecorated ${windowId} ".")"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" decorated"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_is_decorated \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_is_sticky)
				if [ "${val}" = \
				"${window_is_sticky:="$(IsWindowSticky ${windowId} ".")"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" sticky"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_is_sticky \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_desktop_size)
				if [ "${val}" = "${window_desktop_size:="$(DesktopSize)"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_desktop_size \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_desktop_size \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_desktop_workarea)
				if [ "${val}" = \
				"${window_desktop_workarea:="$(DesktopWorkarea)"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_desktop_workarea \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_desktop_workarea \"${val}\""
					rc=""
				fi
				;;
			rule${rule}_check_desktops)
				if [ "${val}" = "${desktopsCount}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches desktopsCount \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match desktopsCount \"${val}\""
					rc=""
				fi
				;;
			*)
				LogPrio="err" _log "rule ${rule}: invalid property \"${prop}\" \"${val}\""
				rc=""
				;;
			esac
		done < <(sort \
		< <(grep -se "^rule${rule}_check_" \
		< <(set)))

		if [ -n "${rc}" ]; then
			setuprules="${setuprules}${rule}${TAB}"
			eval val=\"\${rule${rule}_set_continue:-}\"
			[ -n "${val}" ] || \
				break
		fi
	done
	if [ -n "${setuprules}" ]; then
		(WindowSetup ${windowId} "${setuprules}") &
	else
		[ -z "${Debug}" ] || \
			_log "window ${windowId}: Doesn't match any rule"
	fi
	return ${OK}
}

WindowsUpdate() {
	local windowId window_type pids
	[ -z "${Debug}" ] || \
		_log "current window count ${#}"
	for windowId in $(grep -svwF "$(printf '%s\n' ${WindowIds})" \
	< <(printf '%s\n' "${@}")); do
		[ -z "${IgnoreWindowTypes}" ] || \
			if ! window_type="$(WindowType ${windowId})" || \
			grep -qswEe "_NET_WM_WINDOW_TYPE_($(
			tr -s ' ,|' '|' <<< "${IgnoreWindowTypes}" ))" \
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
	local Rules Debug LogPrio IgnoreWindowTypes txt \
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
	exec >> "${LOGFILE}" 2>&1

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
		echo "Info: ${APPNAME} start ${@}" >&2
		Main "${@}"
	else
		echo "Info: submit ${APPNAME} ${@}" >&2
		((exec "${0}" "${@}" > /dev/null 2>&1) &)
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
	shift
	exec "${0}" start "${@}" &
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
status)
	if pid="$(AlreadyRunning)"; then
		echo "Info: log files" \
			$(ls -Q "${LOGFILE}"{,.xtrace} 2> /dev/null) >&2
	else
		echo "Info: ${APPNAME} is not running for this session" >&2
		exit ${ERR}
	fi
	;;
*)
	echo "Wrong action." >&2
	echo "Valid actions are: start|stop|restart|reload|status" >&2
	exit ${ERR}
	;;
esac
:
