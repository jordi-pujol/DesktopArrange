#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.22 $
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

. /usr/lib/setnewwinprops/libsetnewwinprops.sh

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
	set_delay | \
	set_focus | \
	set_active_desktop)
		return ${ERR}
		;;
	set_position | \
	set_size | \
	set_tile | \
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
	set_killed | \
	set_pointer)
		return ${OK}
		;;
	esac
	LogPrio="err" _log "Invalid action \"${action}\""
}

PointerMove() {
	local windowId="${1}" \
		val="${2}" \
		windowWidth windowHeight windowX windowY windowScreen \
		x y
	WindowGeometry ${windowId}
	x="$(cut -f 1 -s -d ' ' <<< "${val}")"
	[ "${x//%}" != "${x}" ] && \
		let "x=windowWidth*${x//%/\/100},1" || \
		let "x=x,1"
	[ -n "${x}" ] && \
	[ ${x} -ge 0 -a ${x} -lt "${windowWidth}" ] || \
		let "x=windowWidth/2,1"
	y="$(cut -f 2 -s -d ' ' <<< "${val}")"
	[ "${y//%}" != "${y}" ] && \
		let "y=windowHeight*${y//%/\/100},1" || \
		let "y=y,1"
	[ -n "${y}" ] && \
	[ ${y} -ge 0 -a ${y} -lt "${windowHeight}" ] || \
		let "y=windowHeight/2,1"
	[ -z "${Debug}" ] || \
		_log "window ${windowId}: Setting up pointer to (${val})=(${x} ${y})"
	xdotool mousemove --window ${windowId} ${x} ${y} || \
		LogPrio="err" _log "window ${windowId}:" \
			"Error setting up pointer to (${val})=(${x} ${y})"
}

WindowUnshade() {
	local windowId="${1}"
	IsWindowShaded ${windowId} ||  \
		return ${OK}
	[ -z "${Debug}" ] || \
		_log "window ${windowId}: Un-shading"
	wmctrl -i -r ${windowId} -b remove,shade || \
		LogPrio="err" _log "window ${windowId}:" \
			"Error un-shading"
}

WindowUnminimize() {
	local windowId="${1}"
	IsWindowMinimized ${windowId} || \
		return ${OK}
	[ -z "${Debug}" ] || \
		_log "window ${windowId}: Un-minimizing"
	wmctrl -i -r ${windowId} -b remove,hidden || \
		LogPrio="err" _log "window ${windowId}:" \
			"Error un-minimizing"
}

WindowActivate() {
	local windowId="${1}"
	DesktopSetCurrent ${windowId} $(WindowDesktop ${windowId}) || :
	WindowUnminimize ${windowId}
	WindowUnshade ${windowId}
	[[ $(WindowActive) -eq ${windowId} ]] || \
		xdotool windowactivate --sync ${windowId} || \
			WindowExists ${windowId} || \
				return ${ERR}
	xdotool mousemove --window ${windowId} 0 0 || :
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
		WindowActivate ${windowId} || \
			break
		xdotool key --clearmodifiers "${key}"
	done
	setxkbmap ${xkbmap}
}

WindowTile() {
	local windowId="${1}" \
		rule="${2}" \
		val="${3}" \
		windowWidth windowHeight windowX windowY windowScreen \
		w x y tile desktop desktopSize desktopW desktopH

	if tile="$(awk -v rule="${rule}" \
	'$1 == rule {print $0; rc=-1; exit}
	END{exit rc+1}' < "${TILESFILE}")"; then
		w="$(awk 'NF > 1 {print $NF; rc=-1}
		END{exit rc+1}' <<< "${tile}")" || {
			LogPrio="err" _log "window ${w}:" \
				"Error tiling, can't get ID of previous tiled window"
			return ${OK}
		}
		WindowGeometry ${w} || {
			LogPrio="err" _log "window ${w}:" \
				"Error tiling, can't get geometry of previous tiled window"
			return ${OK}
		}
		desktop="$(WindowDesktop ${w})"
		desktopSize="$(DesktopSize ${desktop})"
		desktopW="$(cut -f 1 -s -d 'x' <<< "${desktopSize}")"
		desktopH="$(cut -f 2 -s -d 'x' <<< "${desktopSize}")"
		x="$(cut -f 1 -s -d ' ' <<< "${val}")"
		if [ "${x}" = "x" ]; then
			let "x=windowX,1"
		else
			if [ "${x//%}" != "${x}" ]; then
				let "x=windowX+desktopW*${x//%/\/100},1"
			else
				let "x=windowX+x,1"
			fi
			if [ -n "${x}" ]; then
				if [ ${x} -lt 0 ]; then
					x=0
				elif [ ${x} -ge $((desktopW-windowWidth)) ]; then
					let "x=desktopW-windowWidth-1,1"
				fi
			else
				let "x=windowX,1"
			fi
		fi
		y="$(cut -f 2 -s -d ' ' <<< "${val}")"
		if [ "${y}" = "y" ]; then
			let "y=windowY,1"
		else
			if [ "${y//%}" != "${y}" ]; then
				let "y=windowY+desktopH*${y//%/\/100},1"
			else
				let "y=windowY+y,1"
			fi
			if [ -n "${y}" ]; then
				if [ ${y} -lt 0 ]; then
					y=0
				elif [ ${y} -ge $((desktopH-windowHeight)) ]; then
					let "y=desktopH-windowHeight-1,1"
				fi
			else
				let "y=windowY,1"
			fi
		fi
		WindowActivate ${windowId} || :
		[ ${desktop} -eq $(WindowDesktop ${windowId}) ] || {
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting up tile, moving to desktop ${desktop}"
			xdotool set_desktop_for_window ${windowId} ${desktop} || \
				LogPrio="err" _log "window ${windowId}:" \
				"Error tiling, can't set desktop to ${desktop}"
			sleep 1
			WindowActivate ${windowId} || :
		}
		[ -z "${Debug}" ] || \
			_log "window ${windowId}: Setting up tile, moving to (${val})=(${x} ${y})"
		xdotool windowmove --sync ${windowId} ${x} ${y} || \
			LogPrio="err" _log "window ${windowId}:" \
				"Error tiling, can't move to (${val})=(${x} ${y})"
	fi
	{ awk -v rule="${rule}" \
		'$1 != rule {print $0}' < "${TILESFILE}"
	printf '%s\n' "${tile:-${rule}} ${windowId}"
	} > "${TILESFILE}.part"
	mv -f "${TILESFILE}.part" "${TILESFILE}"
	[ "${Debug}" != "xtrace" ] || \
		LogPrio="debug" _log "window ${windowId}: Tiling:" \
		"${tile:-${rule}} ${windowId}"
}

WindowTiling() {
	local windowId="${1}" \
		rule="${2}" \
		val="${3}" \
		mypid
	mypid=$(ps -o ppid= -C "ps -o ppid= -C ps -o ppid=")
	[ "${Debug}" != "xtrace" ] || \
		LogPrio="debug" _log "Current process id ${mypid}:" \
		"$(ps -h -l ${mypid})"
	_lock_acquire "${TILESFILE}" "${mypid}"
	WindowTile ${windowId} ${rule} "${val}"
	_lock_release "${TILESFILE}"
}

WindowWaitFocus() {
	local windowId="${1}" \
		rule="${2}" \
		waitForFocus="${3}"
	[[ $(WindowActive) -ne ${windowId} ]] || \
		return ${OK}
	if [ -z "${waitForFocus}" ]; then
		[ -z "${Debug}" ] || \
			_log "window ${windowId}: Setting up focus"
		WindowActivate ${windowId} || :
		return ${OK}
	fi
	[ -z "${Debug}" ] || \
		_log "window ${windowId}:" "Waiting to get focus"
	(export windowId LOGFILE Debug BASH_XTRACEFD
	$(CmdWaitFocus ${windowId})) &
	wait ${!} || :
}

WindowSetupRule() {
	local windowId="${1}" \
		rule="${2}" \
		index action val waitForFocus
	[ -z "${Debug}" ] || \
		_log "window ${windowId}:" \
		"Setting up using rule num. ${rule}"

	waitForFocus=""

	while IFS="[= ]" read -r index action val; do
		val="$(_unquote "${val}")"
		! ActionNeedsFocus "${action}" || {
			WindowWaitFocus ${windowId} ${rule} "${waitForFocus}"
			waitForFocus=""
		}
		WindowExists ${windowId} || \
			return ${OK}
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
		set_focus)
			[ -z "${Debug}" ] || \
				_log "window ${windowId}: Setting up focus"
			WindowActivate ${windowId} || :
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
			[ $(WindowDesktop ${windowId}) -ge 0 ] || \
				LogPrio="warn" _log "window ${windowId}:" \
					"window is pinned to all desktops"
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
		set_tile)
			WindowTiling ${windowId} ${rule} "${val}"
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
				WindowUnminimize ${windowId}
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
				WindowUnshade ${windowId}
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
		set_pointer)
			PointerMove ${windowId} "${val}"
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
		rule setupRules

	[ -z "${Debug}" ] || {
		printf "%s='%s'\n" \
			"New window id" ${windowId} \
			"window_title" "$(WindowTitle ${windowId})" \
			"window_state" "$(WindowState ${windowId})" \
			"window_type" "$(WindowType ${windowId})" \
			"window_app_name" "$(WindowAppName ${windowId})" \
			"window_application" "$(WindowApplication ${windowId} 2> /dev/null)" \
			"window_class" "$(WindowClass ${windowId})" \
			"window_role" "$(WindowRole ${windowId} || :)" \
			"window_desktop" "$(WindowDesktop ${windowId})" \
			"window_is_maximized" "$(IsWindowMaximized ${windowId} ".")" \
			"window_is_maximized_horz" "$(IsWindowMaximizedHorz ${windowId} ".")" \
			"window_is_maximized_vert" "$(IsWindowMaximizedVert ${windowId} ".")" \
			"window_is_fullscreen" "$(IsWindowFullscreen ${windowId} ".")" \
			"window_is_minimized" "$(IsWindowMinimized ${windowId} ".")" \
			"window_is_shaded" "$(IsWindowShaded ${windowId} ".")" \
			"window_is_decorated" "$(IsWindowDecorated ${windowId} ".")" \
			"window_is_sticky" "$(IsWindowSticky ${windowId} ".")" \
			"window_desktop_size" "$(DesktopSize)" \
			"window_desktop_workarea" "$(DesktopWorkarea)" \
			"desktopsCount" "$(DesktopsCount)"
	} >> "${LOGFILE}"

	# checking properties of this window
	# we'll set up only the first rule that matches
	setupRules=""
	rule=${NONE}
	while [ $((rule++)) -lt ${Rules} ]; do
		local prop val \
			rc="${AFFIRMATIVE}" \
			checkOthers=""
		[ -z "${Debug}" ] || \
			_log "window ${windowId}: Checking rule num. ${rule}"
		while [ -n "${rc}" ] && \
		IFS="=" read -r prop val; do
			val="$(_unquote "${val}")"
			case "${prop}" in
			check_title)
				if [ "${val}" = "$(WindowTitle ${windowId})" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window title \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window title \"${val}\""
					rc=""
				fi
				;;
			check_state)
				if [ "${val}" = "$(WindowState ${windowId})" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window state \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window state \"${val}\""
					rc=""
				fi
				;;
			check_type)
				if grep -qs -iwF "${val}" <<< "$(WindowType ${windowId})" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window type \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window type \"${val}\""
					rc=""
				fi
				;;
			check_app_name)
				if [ "${val}" = "$(WindowAppName ${windowId})" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window app name \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window app name \"${val}\""
					rc=""
				fi
				;;
			check_application)
				if grep -qs -iwF "${val}" \
				<<< "$(WindowApplication ${windowId} 2> /dev/null)" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window application \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window application \"${val}\""
					rc=""
				fi
				;;
			check_class)
				if grep -qs -iwF "${val}" <<< "$(WindowClass ${windowId})" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window class \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window class \"${val}\""
					rc=""
				fi
				;;
			check_role)
				if grep -qs -iwF "${val}" <<< "$(WindowRole ${windowId})"; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window role \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window role \"${val}\""
					rc=""
				fi
				;;
			check_desktop)
				if [ "${val}" = "$(WindowDesktop ${windowId})" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window desktop \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window desktop \"${val}\""
					rc=""
				fi
				;;
			check_is_maximized)
				if [ "${val}" = "$(IsWindowMaximized ${windowId} ".")" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" maximized"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window is maximized \"${val}\""
					rc=""
				fi
				;;
			check_is_maximized_horz)
				if [ "${val}" = "$(IsWindowMaximizedHorz ${windowId} ".")" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" maximized horizontally"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window is maximized_horz \"${val}\""
					rc=""
				fi
				;;
			check_is_maximized_vert)
				if [ "${val}" = "$(IsWindowMaximizedVert ${windowId} ".")" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" maximized vertically"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window is maximized vert \"${val}\""
					rc=""
				fi
				;;
			check_is_fullscreen)
				if [ "${val}" = "$(IsWindowFullscreen ${windowId} ".")" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" fullscreen"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window_is_fullscreen \"${val}\""
					rc=""
				fi
				;;
			check_is_minimized)
				if [ "${val}" = "$(IsWindowMinimized ${windowId} ".")" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" minimized"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window is minimized \"${val}\""
					rc=""
				fi
				;;
			check_is_shaded)
				if [ "${val}" = "$(IsWindowShaded ${windowId} ".")" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" shaded"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window is shaded \"${val}\""
					rc=""
				fi
				;;
			check_is_decorated)
				if [ "${val}" = "$(IsWindowDecorated ${windowId} ".")" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: is \"${val}\" decorated"
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window is decorated \"${val}\""
					rc=""
				fi
				;;
			check_is_sticky)
				if [ "${val}" = "$(IsWindowSticky ${windowId} ".")" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches sticky \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window is sticky \"${val}\""
					rc=""
				fi
				;;
			check_desktop_size)
				if [ "${val}" = "$(DesktopSize)" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window desktop size \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window desktop size \"${val}\""
					rc=""
				fi
				;;
			check_desktop_workarea)
				if [ "${val}" = "$(DesktopWorkarea)" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: matches window desktop workarea \"${val}\""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId}: doesn't match window desktop workarea \"${val}\""
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
			check_others)
				checkOthers="y"
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
			[ -n "${checkOthers}" ] || \
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
			grep -qswEe "_NET_WM_WINDOW_TYPE_(${IgnoreWindowTypes^^})" \
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
		_lock_acquire "${TILESFILE}" "${$}"
		if grep -qswF "${windowId}" < "${TILESFILE}"; then
			[ "${Debug}" != "xtrace" ] || \
				LogPrio="debug" _log "window ${windowId}: Tile info:" \
				"$(grep -swF "${windowId}" < "${TILESFILE}")"
			awk -v windowId="${windowId}" \
			'{for (i=2; i <= NF; i++)
				if ($i == windowId) {
					for (j=i; j < NF; j++)
						$j=$(j+1)
					NF--
					break
				}
			if (NF > 1) print $0}' < "${TILESFILE}" > "${TILESFILE}.part"
			mv -f "${TILESFILE}.part" "${TILESFILE}"
		fi
		_lock_release "${TILESFILE}"
	done

	WindowIds="${@}"
	return ${OK}
}

Main() {
	# internal variables, daemon scope
	local Rules Debug EmptyList LogPrio IgnoreWindowTypes txt \
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

	set +o xtrace
	if grep -qswF 'xtrace' <<< "${@}"; then
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {BASH_XTRACEFD}> "${LOGFILE}.xtrace"
		exec >> "${LOGFILE}.xtrace" 2>&1
		set -o xtrace
	else
		exec >> "${LOGFILE}" 2>&1
	fi

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
				WindowsUpdate $(tr -s '[:blank:],' ' ' \
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

set -o errexit -o nounset -o pipefail +o noglob -o noclobber

# constants
readonly NAME="$(basename "${0}")" \
	APPNAME="setnewwinprops"
XROOT="$(GetXroot)" || \
	exit ${ERR}
readonly XROOT \
	LOGFILE="/tmp/${APPNAME}/${USER}/${XROOT}" \
	PIDFILE="/tmp/${APPNAME}/${USER}/${XROOT}.pid" \
	PIPE="/tmp/${APPNAME}/${USER}/${XROOT}.pipe" \
	TILESFILE="/tmp/${APPNAME}/${USER}/${XROOT}.tiles"

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
