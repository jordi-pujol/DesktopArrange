#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.26 $
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
		"exec /usr/lib/setnewwinprops/setnewwinprops-waitfocus.sh"
}

ActionNeedsFocus() {
	local action="${1}"
	case "${action}" in
	set_delay | \
	set_focus | \
	set_minimized | \
	set_closed | \
	set_killed | \
	set_desktop | \
	set_active_desktop)
		return ${ERR}
		;;
	set_position | \
	set_size | \
	set_tiled | \
	set_maximized | \
	set_maximized_horz | \
	set_maximized_vert | \
	set_fullscreen | \
	set_mosaicked | \
	set_shaded | \
	set_undecorated | \
	set_pinned | \
	set_sticky | \
	set_above | \
	set_below | \
	set_pointer)
		return ${OK}
		;;
	esac
	LogPrio="err" _log "Invalid action \"${action}\""
}

GetMenuBarHeight() {
	local windowId="${1}" \
		undecorated=0 wY
	[ -z "${MenuBarHeight}" ] || \
		return ${OK}
	MenuBarHeight="$(awk -v var="MenuBarHeight" -F '=' \
		'$1 == var {print $2; exit}' < "${VARSFILE}")"
	[ -z "${MenuBarHeight}" ] || \
		return ${OK}
	IsWindowUndecorated ${windowId} || \
		undecorated="${?}"
	[ ${undecorated} -ne 2 ] || \
		return ${ERR}
	DesktopSize
	WindowGeometry ${windowId}
	wY=${windowY}
	[ ${undecorated} -eq 1 ] || \
		toggle-decorations -e ${windowId}
	xdotool windowmove ${windowId} x ${desktopWorkareaY}
	WindowGeometry ${windowId}
	[ ${undecorated} -eq 1 ] || \
		toggle-decorations -d ${windowId}
	xdotool windowmove ${windowId} x ${wY}
	let "MenuBarHeight=windowY-desktopWorkareaY,1"
	awk -v var="MenuBarHeight" -F '=' \
	'$1 == var {rc=-1; exit}
	END{exit rc+1}' < "${VARSFILE}" || \
		echo "MenuBarHeight=${MenuBarHeight}" >> "${VARSFILE}"
}

PointerMove() {
	local windowId="${1}" \
		rule="${2}" \
		val="${3}" \
		x y
	local windowWidth windowHeight windowX windowY windowScreen
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
		_log "window ${windowId} rule ${rule}: Setting pointer to (${val})=(${x} ${y})"
	xdotool mousemove --window ${windowId} ${x} ${y} || \
		LogPrio="err" _log "window ${windowId} rule ${rule}:" \
			"Error setting pointer to (${val})=(${x} ${y})"
}

WindowUndecorate() {
	local windowId="${1}" \
		rule="${2}" \
		val="${3}" \
		rc=0 \
		state
	state="$(toggle-decorations -s ${windowId})" || \
		return ${OK}
	state="${state##* }"
	[ -z "${Debug}" ] || \
		_log "window ${windowId}:" \
			"Is $([ ${state} -gt 0 ] || echo "un")decorated"
	if [ "${val}" = "${AFFIRMATIVE}" -a ${state} -gt 0 ]; then
		[ -z "${Debug}" ] || \
			_log "window ${windowId} rule ${rule}: Undecorating"
		toggle-decorations -d ${windowId} || :
	elif [ "${val}" = "${NEGATIVE}" -a ${state} -eq 0 ]; then
		[ -z "${Debug}" ] || \
			_log "window ${windowId} rule ${rule}: Decorating"
		toggle-decorations -e ${windowId} || :
	fi
}

WindowUnshade() {
	local windowId="${1}" \
		rule="${2}"
	IsWindowShaded ${windowId} ||  \
		return ${OK}
	[ -z "${Debug}" ] || \
		_log "window ${windowId} rule ${rule}: Un-shading"
	wmctrl -i -r ${windowId} -b remove,shade || \
		LogPrio="err" _log "window ${windowId} rule ${rule}:" \
			"Error un-shading"
}

WindowUnminimize() {
	local windowId="${1}" \
		rule="${2}"
	IsWindowMinimized ${windowId} || \
		return ${OK}
	[ -z "${Debug}" ] || \
		_log "window ${windowId} rule ${rule}: Un-minimizing"
	wmctrl -i -r ${windowId} -b remove,hidden || \
		LogPrio="err" _log "window ${windowId} rule ${rule}:" \
			"Error un-minimizing"
}

WindowActivate() {
	local windowId="${1}" \
		rule="${2}"
	DesktopSetCurrent ${windowId} $(WindowDesktop ${windowId}) || :
	WindowUnminimize ${windowId} ${rule}
	WindowUnshade ${windowId} ${rule}
	[[ $(WindowActive) -eq ${windowId} ]] || \
		xdotool windowactivate ${windowId} || \
			WindowExists ${windowId} || \
				return ${ERR}
	xdotool mousemove --window ${windowId} 0 0 || :
}

WindowTapKeys() {
	local windowId="${1}" \
		rule="${2}" \
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
		WindowActivate ${windowId} ${rule} || \
			break
		xdotool key --clearmodifiers "${key}"
	done
	setxkbmap ${xkbmap}
}

WindowTile() {
	local windowId="${1}" \
		rule="${2}" \
		val="${3}" \
		w x y tile desktop undecorated
	local windowWidth windowHeight windowX windowY windowScreen
	local desktopNum desktopName desktopWidth desktopHeight \
		desktopViewPosX desktopViewPosY \
		desktopWorkareaX desktopWorkareaY desktopWorkareaW desktopWorkareaH

	GetMenuBarHeight ${windowId}
	if tile="$(awk -v rule="${rule}" \
	'$1 == "tile_" rule {print $0; rc=-1; exit}
	END{exit rc+1}' < "${VARSFILE}")"; then
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
		[ "${Debug}" != "xtrace" ] || \
			LogPrio="debug" _log "window ${windowId} rule ${rule}: Tiling:" \
			"${tile:-${rule}} ${windowId}"
		desktop="$(WindowDesktop ${w})"
		DesktopSize ${desktop}
		x="$(cut -f 1 -s -d ' ' <<< "${val}")"
		if [ "${x}" = "x" ]; then
			let "x=windowX,1"
		else
			if [ "${x//%}" != "${x}" ]; then
				let "x=windowX+desktopWidth*${x//%/\/100},1"
			else
				let "x=windowX+x,1"
			fi
			if [ -n "${x}" ]; then
				if [ ${x} -lt ${desktopWorkareaX} ]; then
					x=${desktopWorkareaX}
				elif [ ${x} -ge $((desktopWidth-windowWidth)) ]; then
					let "x=desktopWidth-windowWidth-1,1"
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
				let "y=windowY+desktopHeight*${y//%/\/100},1"
			else
				let "y=windowY+y,1"
			fi
			if [ -n "${y}" ]; then
				if [ ${y} -lt ${desktopWorkareaY} ]; then
					y=${desktopWorkareaY}
				elif [ ${y} -ge $((desktopHeight-windowHeight)) ]; then
					let "y=desktopHeight-windowHeight-1,1"
				fi
			else
				let "y=windowY,1"
			fi
		fi
		WindowActivate ${windowId} ${rule} || :
		[ ${desktop} -eq $(WindowDesktop ${windowId}) ] || {
			[ -z "${Debug}" ] || \
				_log "window ${windowId} rule ${rule}: Tiling, moving to desktop ${desktop}"
			xdotool set_desktop_for_window ${windowId} ${desktop} || \
				LogPrio="err" _log "window ${windowId} rule ${rule}:" \
				"Error tiling, can't set desktop to ${desktop}"
			sleep 1
			WindowActivate ${windowId} ${rule} || :
		}
		undecorated=0
		IsWindowUndecorated ${windowId} || \
			undecorated="${?}"
		[ ${undecorated} -ne 2 ] || \
			return ${ERR}
		[ ${undecorated} -eq 0 ] || \
			let "y-=MenuBarHeight,1"
		[ -z "${Debug}" ] || \
			_log "window ${windowId} rule ${rule}: Tiling, moving to (${val})=(${x} ${y})"
		xdotool windowmove ${windowId} ${x} ${y} || \
			LogPrio="err" _log "window ${windowId} rule ${rule}:" \
				"Error tiling, can't move to (${val})=(${x} ${y})"
	fi
	{ awk -v rule="${rule}" \
		'$1 != "tile_" rule {print $0}' < "${VARSFILE}"
	printf '%s\n' "${tile:-"tile_${rule}"} ${windowId}"
	} > "${VARSFILE}.part"
	mv -f "${VARSFILE}.part" "${VARSFILE}"
	[ "${Debug}" != "xtrace" ] || \
		LogPrio="debug" _log "window ${windowId} rule ${rule}: Tiling:" \
		"${tile:-${rule}} ${windowId}"
}

WindowTiling() {
	local windowId="${1}" \
		rule="${2}" \
		val="${3}"
	_lock_acquire "${VARSFILE}" ${mypid}
	WindowTile ${windowId} ${rule} "${val}"
	_lock_release "${VARSFILE}" ${mypid}
}

WindowMosaic() {
	local windowId="${1}" \
		rule="${2}"  \
		val="${3}" \
		win winCount \
		wW wH w h wX wY mosaic desktop undecorated \
		maxRows maxCols rows cols row col
	local windowWidth windowHeight windowX windowY windowScreen
	local desktopNum desktopName desktopWidth desktopHeight \
		desktopViewPosX desktopViewPosY \
		desktopWorkareaX desktopWorkareaY desktopWorkareaW desktopWorkareaH

	GetMenuBarHeight ${windowId}
	if mosaic="$(awk -v rule="${rule}" \
	'$1 == "mosaic_" rule {print $0; rc=-1; exit}
	END{exit rc+1}' < "${VARSFILE}")"; then
		let "winCount=$(wc -w <<< "${mosaic}"),1"
	else
		winCount=1
	fi
	maxCols="$(cut -f 1 -s -d ' ' <<< "${val}")"
	maxRows="$(cut -f 2 -s -d ' ' <<< "${val}")"
	rows=0
	cols=0
	if [ ${maxCols} -ne 0 ]; then
		let "rows = winCount%maxCols == 0 ? winCount/maxCols : (winCount/maxCols)+1 ,1"
		let "cols = winCount%rows == 0 ? winCount/rows : (winCount/rows)+1 ,1"
	elif [ ${maxRows} -ne 0 ]; then
		let "cols = winCount%maxRows == 0 ? winCount/maxRows : (winCount/maxRows)+1 ,1"
		let "rows = winCount%cols == 0 ? winCount/cols : (winCount/cols)+1 ,1"
	fi
	[ "${Debug}" != "xtrace" ] || \
		LogPrio="debug" _log "window ${windowId} rule ${rule}: Mosaic:" \
		"${cols} columns, ${rows} rows"
	DesktopSize
	desktop=""
	col=0
	row=0
	let "wW=(desktopWorkareaW/cols)-5,1"
	let "wH=(desktopWorkareaH/rows)-5,1"
	for win in ${mosaic#* } ${windowId}; do
		[ -n "${desktop}" ] || \
			desktop="$(WindowDesktop ${win})"
		if [ ${col} -eq 0 ]; then
			let "row++,1"
		fi
		let "col++,1"
		let "wX=desktopWorkareaX+(wW+5)*(col-1),1"
		let "wY=desktopWorkareaY+(wH+3)*(row-1),1"
		WindowActivate ${win} ${rule} || :
		[ ${desktop} -eq $(WindowDesktop ${win}) ] || {
			[ -z "${Debug}" ] || \
				_log "window ${win}: Mosaic, moving to desktop ${desktop}"
			xdotool set_desktop_for_window ${win} ${desktop} || \
				LogPrio="err" _log "window ${win}:" \
				"Error mosaic, can't move to desktop ${desktop}"
			sleep 1
			WindowActivate ${win} ${rule} || :
		}
		undecorated=0
		IsWindowUndecorated ${win} || \
			undecorated="${?}"
		[ ${undecorated} -ne 2 ] || \
			continue
		w="${wW}"
		[ ${undecorated} -ne 0 ] && \
			let "h=wH-(MenuBarHeight/2),1" || \
			h=${wH}
		wmctrl -i -r ${win} -b remove,maximized_horz,maximized_vert,minimized || \
			LogPrio="err" _log "window ${windowId} rule ${rule}:" \
				"Error mosaic remove,maximized_horz,maximized_vert,minimized"
		xdotool windowsize ${win} "${w}" "${h}" || \
				LogPrio="err" _log "window ${win}:" \
					"Error setting size to (${w} ${h})"
		xdotool windowmove ${win} "${wX}" "${wY}" || \
			LogPrio="err" _log "window ${win}:" \
				"Error mosaic, can't move to (${wX} ${wY})"
		if [ ${col} -ge ${cols} ]; then
			col=0
		fi
	done
	{ awk -v rule="${rule}" \
		'$1 != "mosaic_" rule {print $0}' < "${VARSFILE}"
	printf '%s\n' "${mosaic:-"mosaic_${rule}"} ${windowId}"
	} > "${VARSFILE}.part"
	mv -f "${VARSFILE}.part" "${VARSFILE}"
	[ "${Debug}" != "xtrace" ] || \
		LogPrio="debug" _log "window ${windowId} rule ${rule}: Mosaic:" \
		"${mosaic:-${rule}} ${windowId}"
}

WindowEnmossay() {
	local windowId="${1}" \
		rule="${2}" \
		val="${3}"
	_lock_acquire "${VARSFILE}" ${mypid}
	WindowMosaic ${windowId} ${rule} "${val}" || :
	_lock_release "${VARSFILE}" ${mypid}
}

WindowPosition() {
	local windowId="${1}" \
		rule="${2}" \
		val="${3}" \
		x y desktop
	local windowWidth windowHeight windowX windowY windowScreen
	local desktopNum desktopName desktopWidth desktopHeight \
		desktopViewPosX desktopViewPosY \
		desktopWorkareaX desktopWorkareaY desktopWorkareaW desktopWorkareaH

	WindowGeometry ${windowId} || {
		LogPrio="err" _log "window ${windowId} rule ${rule}:" \
			"Error setting position, can't get window geometry"
		return ${OK}
	}
	desktop="$(WindowDesktop ${windowId})"
	DesktopSize ${desktop}

	_lock_acquire "${VARSFILE}" ${mypid}
	GetMenuBarHeight ${windowId}
	_lock_release "${VARSFILE}" ${mypid}

	x="$(cut -f 1 -s -d ' ' <<< "${val}")"
	case "${x}" in
	left)
		x=${desktopWorkareaX}
		;;
	right)
		let "x=desktopWorkareaX+desktopWorkareaW-windowWidth,1"
		;;
	center)
		let "x=desktopWorkareaX+(desktopWorkareaW-windowWidth)/2,1"
		;;
	esac

	y="$(cut -f 2 -s -d ' ' <<< "${val}")"
	case "${y,,}" in
	top)
		y=${desktopWorkareaY}
		;;
	bottom)
		if IsWindowUndecorated ${windowId}; then
			let "y=desktopWorkareaY+desktopWorkareaH-windowHeight,1"
		else
			let "y=desktopWorkareaY+desktopWorkareaH-windowHeight-MenuBarHeight/2,1"
		fi
		;;
	center)
		if IsWindowUndecorated ${windowId}; then
			let "y=desktopWorkareaY+(desktopWorkareaH-windowHeight)/2,1"
		else
			let "y=desktopWorkareaY-MenuBarHeight+(desktopWorkareaH-windowHeight)/2,1"
		fi
		;;
	esac
	[ -z "${Debug}" ] || \
		_log "window ${windowId} rule ${rule}: Moving to (${val})=(${x} ${y})"
	xdotool windowmove ${windowId} "${x}" "${y}" || \
		LogPrio="err" _log "window ${windowId} rule ${rule}:" \
			"Error moving to (${val})=(${x} ${y})"
}

WindowWaitFocus() {
	local windowId="${1}" \
		rule="${2}" \
		waitForFocus="${3}"
	[[ $(WindowActive) -ne ${windowId} ]] || \
		return ${OK}
	if [ -z "${waitForFocus}" ]; then
		[ -z "${Debug}" ] || \
			_log "window ${windowId} rule ${rule}: Setting up focus"
		WindowActivate ${windowId} ${rule} || :
		return ${OK}
	fi
	[ -z "${Debug}" ] || \
		_log "window ${windowId} rule ${rule}:" "Waiting to get focus"
	(export windowId LOGFILE Debug BASH_XTRACEFD
	$(CmdWaitFocus ${windowId})) &
	wait ${!} || :
}

WindowSetupRule() {
	local windowId="${1}" \
		rule="${2}" \
		index action val waitForFocus
	[ -z "${Debug}" ] || \
		_log "window ${windowId} rule ${rule}:" \
		"Setting up"

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
				_log "window ${windowId} rule ${rule}:" \
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
				_log "window ${windowId} rule ${rule}: Setting up focus"
			WindowActivate ${windowId} ${rule} || :
			;;
		set_active_desktop)
			if [ ${val} -lt $(DesktopsCount) ]; then
				if [ ${val} -ne $(DesktopCurrent) ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Setting up active desktop ${val}"
					xdotool set_desktop ${val} || {
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error setting active desktop ${val}"
					}
				fi
			else
				LogPrio="err" _log "window ${windowId} rule ${rule}:" \
					"Can't set invalid active desktop ${val}"
			fi
			;;
		set_desktop)
			[ $(WindowDesktop ${windowId}) -ge 0 ] || \
				LogPrio="warn" _log "window ${windowId} rule ${rule}:" \
					"window is pinned to all desktops"
			if [ ${val} -lt $(DesktopsCount) ]; then
				c=0
				while [ $((c++)) -lt 5 ]; do
					[ ${c} -eq 1 ] || \
						sleep 1
					[ ${val} -ne $(WindowDesktop ${windowId}) ] || \
						break
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Moving window to desktop ${val}"
					xdotool set_desktop_for_window ${windowId} ${val} || \
						break
				done
			fi
			[ ${val} -eq $(WindowDesktop ${windowId}) ] || \
				LogPrio="err" _log "window ${windowId} rule ${rule}:" \
					"Can't move window to desktop ${val}"
			;;
		set_position)
			WindowPosition ${windowId} ${rule} "${val}"
			;;
		set_size)
			[ -z "${Debug}" ] || \
				_log "window ${windowId} rule ${rule}: Setting size to ${val}"
			xdotool windowsize ${windowId} ${val} || \
				LogPrio="err" _log "window ${windowId} rule ${rule}:" \
					"Error setting size to ${val}"
			;;
		set_tiled)
			WindowTiling ${windowId} ${rule} "${val}"
			;;
		set_maximized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Maximizing"
					wmctrl -i -r ${windowId} -b add,maximized_horz,maximized_vert || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error maximizing"
				}
			else
				! IsWindowMaximized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Un-maximizing"
					wmctrl -i -r ${windowId} -b remove,maximized_horz,maximized_vert || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error un-maximizing"
				}
			fi
			;;
		set_maximized_horz)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximized_horz ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Maximizing horizontally"
					wmctrl -i -r ${windowId} -b add,maximized_horz || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error maximizing horizontally"
				}
			else
				! IsWindowMaximized_horz ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Un-maximizing horizontally"
					wmctrl -i -r ${windowId} -b remove,maximized_horz || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error un-maximizing horizontally"
				}
			fi
			;;
		set_maximized_vert)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximized_vert ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Maximizing vertically"
					wmctrl -i -r ${windowId} -b add,maximized_vert || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error maximizing vertically"
				}
			else
				! IsWindowMaximized_vert ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Un-maximizing vertically "
					wmctrl -i -r ${windowId} -b remove,maximized_vert || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error un-maximizing vertically"
				}
			fi
			;;
		set_fullscreen)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowFullscreen ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Enabling fullscreen"
					wmctrl -i -r ${windowId} -b add,fullscreen || \
							LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error enabling fullscreen"
				}
			else
				! IsWindowFullscreen ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Disabling fullscreen"
					wmctrl -i -r ${windowId} -b remove,fullscreen || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error disabling fullscreen"
				}
			fi
			;;
		set_mosaicked)
			WindowEnmossay ${windowId} ${rule} "${val}"
			;;
		set_minimized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMinimized ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Minimizing"
					xdotool windowminimize ${windowId} || \
					LogPrio="err" _log "window ${windowId} rule ${rule}:" \
						"Error minimizing"
				}
			else
				WindowUnminimize ${windowId} ${rule}
			fi
			;;
		set_shaded)
			rc=0
			IsWindowShaded ${windowId} || \
				rc=${?}
			if [ "${val}" = "${AFFIRMATIVE}"  -a \
			\( ${rc} -eq 1 -o ${rc} -eq 2 \) ]; then
				[ -z "${Debug}" ] || \
					_log "window ${windowId} rule ${rule}: Shading"
				wmctrl -i -r ${windowId} -b add,shade || \
					LogPrio="err" _log "window ${windowId} rule ${rule}:" \
						"Error shading"
			elif [ "${val}" = "${NEGATIVE}"  -a \
			\( ${rc} -eq 0 -o ${rc} -eq 2 \) ]; then
				WindowUnshade ${windowId} ${rule}
			fi
			;;
		set_undecorated)
			WindowUndecorate ${windowId} ${rule} "${val}"
			;;
		set_sticky)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowSticky ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Sticking"
					wmctrl -i -r ${windowId} -b add,sticky || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error sticking"
				}
			else
				! IsWindowSticky ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Un-sticking"
					wmctrl -i -r ${windowId} -b remove,sticky || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error un-sticking"
				}
			fi
			;;
		set_above)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowBelow ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Disabling below"
					wmctrl -i -r ${windowId} -b remove,below || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error disabling below"
				}
				IsWindowAbove ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Enabling above"
					wmctrl -i -r ${windowId} -b add,above || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error enabling above"
				}
			else
				! IsWindowAbove ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Disabling above"
					wmctrl -i -r ${windowId} -b remove,above || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error disabling above"
				}
			fi
			;;
		set_below)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowAbove ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Disabling above"
					wmctrl -i -r ${windowId} -b remove,above || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error disabling above"
				}
				IsWindowBelow ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Enabling below"
					wmctrl -i -r ${windowId} -b add,below || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error enabling below"
				}
			else
				! IsWindowBelow ${windowId} || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Disabling below"
					wmctrl -i -r ${windowId} -b remove,below || \
						LogPrio="err" _log "window ${windowId} rule ${rule}:" \
							"Error disabling below"
				}
			fi
			;;
		set_pinned)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				[ $(WindowDesktop ${windowId}) -eq -1 ] || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Pinning to all desktops"
					xdotool set_desktop_for_window ${windowId} "-1"
				}
			else
				[ $(WindowDesktop ${windowId}) -ne -1 ] || {
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: Un-pinning to all desktops"
					xdotool set_desktop_for_window $(DesktopCurrent)
				}
			fi
			;;
		set_closed)
			[ -z "${Debug}" ] || \
				_log "window ${windowId} rule ${rule}: Closing window"
			xdotool windowclose ${windowId} || \
				LogPrio="err" _log "window ${windowId} rule ${rule}:" \
					"Error closing window"
			;;
		set_killed)
			[ -z "${Debug}" ] || \
				_log "window ${windowId} rule ${rule}: Killing window"
			xdotool windowkill ${windowId} || \
				LogPrio="err" _log "window ${windowId} rule ${rule}:" \
					"Error killing window"
			;;
		set_pointer)
			PointerMove ${windowId} ${rule} "${val}"
			;;
		*)
			LogPrio="err" _log "window ${windowId} rule ${rule}:" \
				"Rule ${rule}, invalid action ${action}='${val}'"
			;;
		esac
	done < <(sort --numeric --key 1,1 \
		< <(sed -nre "\|^rule${rule}_([[:digit:]]+)_(set_.*)|s||\1 \2|p" \
		< <(set)))

	[ -z "${Debug}" ] || \
		_log "window ${windowId} rule ${rule}: End setting up"
}

WindowSetup() {
	local windowId="${1}" \
		setupRules="${2}" \
		rule mypid

	mypid="$(echo $(ps -o ppid= -C "ps -o ppid= -C ps -o ppid="))"

	[ -z "${Debug}" ] || \
		_log "window ${windowId}: Applying rules" \
		"( $(tr -s '[:blank:],' ',' < <(echo ${setupRules})) )"
	for rule in ${setupRules}; do
		WindowSetupRule ${windowId} ${rule} || {
			_log "window ${windowId} rule ${rule}: Error setting rule"
			break
		}
	done
	[ -z "${Debug}" ] || \
		_log "window ${windowId}: End applying rules" \
		"( $(tr -s '[:blank:],' ',' < <(echo ${setupRules})) )"
}

WindowNew() {
	local windowId="${1}" \
		rule setupRules \
		propName netState \
		index prop val deselected \
		rc selectOthers
	local desktopNum desktopName desktopWidth desktopHeight \
		desktopViewPosX desktopViewPosY \
		desktopWorkareaX desktopWorkareaY desktopWorkareaW desktopWorkareaH

	[ -z "${Debug}" ] || {
		DesktopSize $(WindowDesktop ${windowId})
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
			"window_is_maximized_horz" "$(IsWindowMaximized_horz ${windowId} ".")" \
			"window_is_maximized_vert" "$(IsWindowMaximized_vert ${windowId} ".")" \
			"window_is_fullscreen" "$(IsWindowFullscreen ${windowId} ".")" \
			"window_is_minimized" "$(IsWindowMinimized ${windowId} ".")" \
			"window_is_shaded" "$(IsWindowShaded ${windowId} ".")" \
			"window_is_undecorated" "$(IsWindowUndecorated ${windowId} ".")" \
			"window_is_sticky" "$(IsWindowSticky ${windowId} ".")" \
			"window_desktop_size" "${desktopWidth}x${desktopHeight}" \
			"window_desktop_workarea" \
			"${desktopWorkareaX},${desktopWorkareaY} ${desktopWorkareaW}x${desktopWorkareaH}" \
			"desktopsCount" "$(DesktopsCount)"
	} >> "${LOGFILE}"

	# checking properties of this window
	# we'll set up only the first rule that matches,
	# unless that this rule contains the command "select others"
	setupRules=""
	rule=${NONE}
	while [ $((rule++)) -lt ${Rules} ]; do
		rc="${AFFIRMATIVE}"
		selectOthers=""
		[ -z "${Debug}" ] || \
			_log "window ${windowId} rule ${rule}: Checking"
		while [ -n "${rc}" ] && \
		IFS="[= ]" read -r index prop val; do
			val="$(_unquote "${val}")"
			if [ "${prop}" = "select_title" ]; then
				deselected=""
				[ "${val:0:1}" != "!" ] || {
					deselected="!"
					val="${val:1}"
				}
				if [ "${val}" = "$(WindowTitle ${windowId})" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window title \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window title \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				continue
			fi
			val="$(_trim "${val,,}")"
			deselected=""
			[ "${val:0:1}" != "!" ] || {
				deselected="!"
				val="$(_trim "${val:1}")"
			}
			case "${prop}" in
			select_state)
				if [ "${val}" = "$(WindowState ${windowId})" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window state \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window state \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_type)
				if grep -qs -iF "${val}" <<< "$(WindowType ${windowId})" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window type \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window type \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_app_name)
				if [ "${val}" = "$(WindowAppName ${windowId})" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window app name \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window app name \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_application)
				if grep -qs -iwF "${val}" \
				<<< "$(WindowApplication ${windowId} 2> /dev/null)" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window application \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window application \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_class)
				if grep -qs -iwF "${val}" <<< "$(WindowClass ${windowId})" ; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window class \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window class \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_role)
				if grep -qs -iwF "${val}" <<< "$(WindowRole ${windowId})"; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window role \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window role \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_desktop)
				if [ "${val}" = "$(WindowDesktop ${windowId})" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window desktop \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window desktop \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_maximized | \
			select_maximized_horz | \
			select_maximized_vert | \
			select_fullscreen | \
			select_minimized | \
			select_shaded | \
			select_undecorated | \
			select_sticky)
				propName="$(cut -f 2 -s -d '_' <<< "${prop}")"
				netState="$(IsWindow${propName^} ${windowId} ".")"
				case "${netState}" in
				${AFFIRMATIVE} | \
				${NEGATIVE})
					if [ "${val}" = "${netState}" ]; then
						[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: ${propName} is \"${val}\""
					else
						[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: ${propName} is not \"${val}\""
						rc=""
					fi
					;;
				*)
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: ${propName} has an invalid state"
					rc=""
					;;
				esac
				;;
			select_desktop_size)
				DesktopSize $(WindowDesktop ${windowId})
				if [ "${val}" = "${desktopWidth}x${desktopHeight}" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window desktop size \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window desktop size \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_desktop_workarea)
				if [ "${val}" = \
				"${desktopWorkareaX},${desktopWorkareaY} ${desktopWorkareaW}x${desktopWorkareaH}" \
				]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches window desktop workarea \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match window desktop workarea \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_desktops)
				if [ "${val}" = "$(DesktopsCount)" ]; then
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: matches desktopsCount \"${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					[ -z "${Debug}" ] || \
						_log "window ${windowId} rule ${rule}: doesn't match desktopsCount \"${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_others)
				selectOthers="y"
				[ -z "${Debug}" ] || \
					_log "window ${windowId} rule ${rule}: enabling \"select others\""
				;;
			*)
				LogPrio="err" _log "rule ${rule}: invalid property \"${prop}\" \"${deselected}${val}\""
				rc=""
				;;
			esac
		done < <(sort --numeric --key 1,1 \
		< <(sed -nre "\|^rule${rule}_([[:digit:]]+)_(select_.*)|s||\1 \2|p" \
		< <(set)))

		if [ -n "${rc}" ]; then
			[ -z "${Debug}" ] || \
				_log "window ${windowId} rule ${rule}: End check, this rule is selected"
			setupRules="${setupRules}${rule}${TAB}"
			[ -n "${selectOthers}" ] || \
				break
			[ -z "${Debug}" ] || \
				_log "window ${windowId} rule ${rule}: continue checking other rules"
		else
			[ -z "${Debug}" ] || \
				_log "window ${windowId} rule ${rule}: End check, doesn't match"
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
		_lock_acquire "${VARSFILE}" ${$}
		if grep -qswF "${windowId}" < "${VARSFILE}"; then
			[ "${Debug}" != "xtrace" ] || \
				LogPrio="debug" _log "window ${windowId}: Tile info:" \
				"$(grep -swF "${windowId}" < "${VARSFILE}")"
			awk -v windowId="${windowId}" \
			'{for (i=2; i <= NF; i++)
				if ($i == windowId) {
					for (j=i; j < NF; j++)
						$j=$(j+1)
					NF--
					break
				}
			if (NF > 1) print $0}' < "${VARSFILE}" > "${VARSFILE}.part"
			mv -f "${VARSFILE}.part" "${VARSFILE}"
		fi
		_lock_release "${VARSFILE}" ${$}
	done

	WindowIds="${@}"
	return ${OK}
}

Main() {
	# internal variables, daemon scope
	local Rules Debug EmptyList LogPrio IgnoreWindowTypes txt \
		WindowIds="" MenuBarHeight=""

	trap '_exit' EXIT
	trap 'exit' INT
	trap 'echo reload >> "${PIPE}"' HUP

	mkdir -p -m 0777 "/tmp/${APPNAME}"
	mkdir -p "/tmp/${APPNAME}/${USER}"
	rm -f "${LOGFILE}"*

	echo ${$} > "${PIDFILE}"

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
			if [ -z "${MenuBarHeight}" ]; then
				_lock_acquire "${VARSFILE}" ${$}
				MenuBarHeight="$(awk \
				-v var="MenuBarHeight" -F '=' \
				'$1 == var {print $2; exit}' < "${VARSFILE}")"
				_lock_release "${VARSFILE}" ${$}
			fi
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
	VARSFILE="/tmp/${APPNAME}/${USER}/${XROOT}.vars"

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
