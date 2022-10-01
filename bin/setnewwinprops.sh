#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.20 $
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

ActionNeedsFocus() {
	local action="${1}"
	case "${action}" in
	set_ignore | \
	set_delay | \
	set_focus | \
	set_active_desktop)
		return ${ERR}
		;;
	set_position | \
	set_size | \
	set_maximized | \
	set_maximized_horizontally | \
	set_maximized_vertically | \
	set_fullscreen | \
	set_minimized | \
	set_shaded | \
	set_decorated | \
	set_pinned | \
	set_sticky | \
	set_above | \
	set_below | \
	set_desktop | \
	set_closed | \
	set_killed)
		return ${OK}
		;;
	esac
	LogPrio="err" _log "Invalid action \"${action}\""
}

WindowWaitFocus() {
	local windowId="${1}" \
		rule="${2}" \
		waitForFocus="${3}"
	if [[ $(WindowActive) -ne ${windowId} ]]; then
		if [ -z "${waitForFocus}" ]; then
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting up focus"
			WindowSetActive ${windowId} || \
				return ${OK}
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
		index action val waitForFocus
	[ -z "${Debug}" ] || \
		_log "window ${windowId}:" \
		"Setting up using rule num. ${rule}"

	waitForFocus=""

	eval val=\"\${rule${rule}_set_ignore:-}\"
	if [ -n "${val}" ]; then
		[ -z "${Debug}" ] || \
			_log "window ${windowId}:" \
			"Ignored"
		return ${OK}
	fi

	while IFS="[= ]" read -r index action val; do
		val="$(_unquote "${val}")"
		WindowExists ${windowId} || \
			return ${OK}
		! ActionNeedsFocus "${action}" || {
			WindowWaitFocus ${windowId} ${rule} "${waitForFocus}"
			waitForFocus=""
		}
		case "${action}" in
		set_delay)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}:" \
				"Waiting ${val} seconds to set up"
			waitForFocus="y"
			while [ $((val--)) -ge ${NONE} ]; do
				sleep 1
				WindowExists ${windowId} || \
					break
			done
			;;
		set_active_desktop)
			if [ ${val} -lt $(DesktopsCount) ]; then
				if [ ${val} -ne $(DesktopCurrent) ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Setting up active desktop ${val}"
					xdotool set_desktop ${val} || {
						LogPrio="err" _log "window ${windowId}:" \
							"Error setting active desktop ${val}"
					}
				fi
			else
				LogPrio="err" _log "window ${windowId}:" \
					"Can't set invalid active desktop ${val}"
			fi
			;;
		set_desktop)
			if [ $(WindowDesktop ${windowId}) -lt 0 ]; then
				LogPrio="warn" _log "window ${windowId}:" \
					"Can't move this sticky window to any desktop"
			else
				if [ ${val} -lt $(DesktopsCount) ]; then
					c=0
					while [ $((c++)) -lt 5 ]; do
						[ ${c} -eq 1 ] || \
							sleep 1
						[ ${val} -ne $(WindowDesktop ${windowId}) ] || \
							break
						[ -z "${Debug}" ] || \
							_log "window ${windowId}: Moving window to desktop ${val}"
						xdotool set_desktop_for_window ${windowId} ${val} || \
							break
					done
				fi
				[ ${val} -eq $(WindowDesktop ${windowId}) ] || \
					LogPrio="err" _log "window ${windowId}:" \
						"Can't move window to desktop ${val}"
			fi
			;;
		set_position)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Moving to ${val}"
			xdotool windowmove --sync ${windowId} ${val} || \
				LogPrio="err" _log "window ${windowId}:" \
					"Error moving to ${val}"
			;;
		set_size)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting up size to ${val}"
			xdotool windowsize --sync ${windowId} ${val} || \
				LogPrio="err" _log "window ${windowId}:" \
					"Error setting up size to ${val}"
			;;
		set_maximized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing"
					wmctrl -i -r ${windowId} -b add,maximized_horz,maximized_vert || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error maximizing"
				}
			else
				! IsWindowMaximized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing"
					wmctrl -i -r ${windowId} -b remove,maximized_horz,maximized_vert || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error un-maximizing"
				}
			fi
			;;
		set_maximized_horizontally)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximizedHorz ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing horizontally"
					wmctrl -i -r ${windowId} -b add,maximized_horz || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error maximizing horizontally"
				}
			else
				! IsWindowMaximizedHorz ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing horizontally"
					wmctrl -i -r ${windowId} -b remove,maximized_horz || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error un-maximizing horizontally"
				}
			fi
			;;
		set_maximized_vertically)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximizedVert ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Maximizing vertically"
					wmctrl -i -r ${windowId} -b add,maximized_vert || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error maximizing vertically"
				}
			else
				! IsWindowMaximizedVert ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-maximizing vertically "
					wmctrl -i -r ${windowId} -b remove,maximized_vert || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error un-maximizing vertically"
				}
			fi
			;;
		set_fullscreen)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowFullscreen ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Enabling fullscreen"
					wmctrl -i -r ${windowId} -b add,fullscreen || \
							LogPrio="err" _log "window ${windowId}:" \
							"Error enabling fullscreen"
				}
			else
				! IsWindowFullscreen ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling fullscreen"
					wmctrl -i -r ${windowId} -b remove,fullscreen || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error disabling fullscreen"
				}
			fi
			;;
		set_minimized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMinimized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Minimizing"
					xdotool windowminimize --sync ${windowId} || \
					LogPrio="err" _log "window ${windowId}:" \
						"Error minimizing"
				}
			else
				! IsWindowMinimized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-minimizing"
					wmctrl -i -r ${windowId} -b add,maximized_horz,maximized_vert || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error un-minimizing, add,maximized_horz,maximized_vert"
					sleep 0.1
					wmctrl -i -r ${windowId} -b remove,maximized_horz,maximized_vert || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error un-minimizing, remove,maximized_horz,maximized_vert"
				}
			fi
			;;
		set_shaded)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowShaded ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Shading"
					wmctrl -i -r ${windowId} -b add,shade || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error shading"
				}
			else
				! IsWindowShaded ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-shading"
					wmctrl -i -r ${windowId} -b remove,shade || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error un-shading"
				}
			fi
			;;
		set_decorated)
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
		set_pinned)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				[ $(WindowDesktop ${windowId}) -eq -1 ] || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Pinning to all desktops"
					xdotool set_desktop_for_window ${windowId} "-1"
				}
			else
				[ $(WindowDesktop ${windowId}) -ne -1 ] || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-pinning to all desktops"
					xdotool set_desktop_for_window $(DesktopCurrent)
				}
			fi
			;;
		set_sticky)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowSticky ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Sticking"
					wmctrl -i -r ${windowId} -b add,sticky || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error sticking"
				}
			else
				! IsWindowSticky ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Un-sticking"
					wmctrl -i -r ${windowId} -b remove,sticky || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error un-sticking"
				}
			fi
			;;
		set_above)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowBelow ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling below"
					wmctrl -i -r ${windowId} -b remove,below || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error disabling below"
				}
				IsWindowAbove ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Enabling above"
					wmctrl -i -r ${windowId} -b add,above || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error enabling above"
				}
			else
				! IsWindowAbove ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling above"
					wmctrl -i -r ${windowId} -b remove,above || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error disabling above"
				}
			fi
			;;
		set_below)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowAbove ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling above"
					wmctrl -i -r ${windowId} -b remove,above || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error disabling above"
				}
				IsWindowBelow ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Enabling below"
					wmctrl -i -r ${windowId} -b add,below || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error enabling below"
				}
			else
				! IsWindowBelow ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: Disabling below"
					wmctrl -i -r ${windowId} -b remove,below || \
						LogPrio="err" _log "window ${windowId}:" \
							"Error disabling below"
				}
			fi
			;;
		set_closed)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Closing window"
			xdotool windowclose ${windowId} || \
				LogPrio="err" _log "window ${windowId}:" \
					"Error closing window"
			;;
		set_killed)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Killing window"
			xdotool windowkill ${windowId} || \
				LogPrio="err" _log "window ${windowId}:" \
					"Error killing window"
			;;
		set_focus)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting up focus"
			WindowSetActive ${windowId} || :
			;;
		*)
			LogPrio="err" _log "window ${windowId}:" \
				"Rule ${rule}, invalid action ${action}='${val}'"
			;;
		esac
	done < <(sort --numeric --key 1,1 \
		< <(sed -nre "\|^rule${rule}_([[:digit:]]+)_(set_.*)|s||\1 \2|p" \
		< <(set)))

	[ -z "${Debug}" ] || \
		_log "window ${windowId}: End setup rule num. ${rule}"
}

WindowSetup() {
	local windowId="${1}" \
		setupRules="${2}" \
		rule

	[ -z "${Debug}" ] || \
		_log "window ${windowId}: Setting up rules" \
		"$(tr -s '[:blank:],' ',' < <(echo ${setupRules}))"
	for rule in ${setupRules}; do
		WindowSetupRule ${windowId} ${rule}
	done
	[ -z "${Debug}" ] || \
		_log "window ${windowId}: End setup rules" \
		"$(tr -s '[:blank:],' ',' < <(echo ${setupRules}))"
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
		rule setupRules

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
			"desktopsCount" "$(DesktopsCount)"
	} >> "${LOGFILE}"

	# checking properties of this window
	# we'll set up only the first rule that matches
	setupRules=""
	rule=${NONE}
	while [ $((rule++)) -lt ${Rules} ]; do
		local rc="${AFFIRMATIVE}" prop val check_continue=""
		[ -z "${Debug}" ] || \
			_log "window ${windowId}: Checking rule num. ${rule}"
		while [ -n "${rc}" ] && \
		IFS="=" read -r prop val; do
			val="$(_unquote "${val}")"
			case "${prop}" in
			check_title)
				if [ "${val}" = "${window_title:="$(WindowTitle ${windowId})"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_title \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_title \"${val}\""
					rc=""
				fi
				;;
			check_state)
				if [ "${val}" = "${window_state:="$(WindowState ${windowId})"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_state \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_state \"${val}\""
					rc=""
				fi
				;;
			check_type)
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
			check_app_name)
				if [ "${val}" = "${window_app_name:="$(WindowAppName ${windowId})"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_app_name \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_app_name \"${val}\""
					rc=""
				fi
				;;
			check_application)
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
			check_class)
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
			check_role)
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
			check_desktop)
				if [ "${val}" = "${window_desktop:="$(WindowDesktop ${windowId})"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_desktop \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_desktop \"${val}\""
					rc=""
				fi
				;;
			check_is_maximized)
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
			check_is_maximized_horz)
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
			check_is_maximized_vert)
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
			check_is_fullscreen)
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
			check_is_minimized)
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
			check_is_shaded)
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
			check_is_decorated)
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
			check_is_sticky)
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
			check_desktop_size)
				if [ "${val}" = "${window_desktop_size:="$(DesktopSize)"}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window_desktop_size \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_desktop_size \"${val}\""
					rc=""
				fi
				;;
			check_desktop_workarea)
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
			check_desktops)
				if [ "${val}" = "$(DesktopsCount)" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches desktopsCount \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match desktopsCount \"${val}\""
					rc=""
				fi
				;;
			check_continue)
				check_continue="y"
				;;
			*)
				LogPrio="err" _log "rule ${rule}: invalid property \"${prop}\" \"${val}\""
				rc=""
				;;
			esac
		done < <(sort \
		< <(sed -ne "/^rule${rule}_check_/ {/^rule${rule}_/s///p}" \
		< <(set)))

		if [ -n "${rc}" ]; then
			setupRules="${setupRules}${rule}${TAB}"
			[ -n "${check_continue}" ] || \
				break
		fi
	done
	if [ -n "${setupRules}" ]; then
		(WindowSetup ${windowId} "${setupRules}") &
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
