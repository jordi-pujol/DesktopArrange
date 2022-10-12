#!/bin/bash

#************************************************************************
#  DesktopArrange
#
#  Arrange Linux worskpaces
#  according to a set of configurable rules.
#
#  $Revision: 0.30 $
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

. /usr/lib/desktoparrange/libdesktoparrange.sh

_exit() {
	local pidsChildren
	trap - EXIT INT HUP
	set +o xtrace
	LogPrio="warn" \
	_log "exit"
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
		"exec /usr/lib/desktoparrange/desktoparrange-endwaiting.sh"
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
	set_pointer | \
	set_tap_keys | \
	set_type_text)
		return ${OK}
		;;
	esac
	LogPrio="err" \
	_log "invalid action \"${action}\""
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
		ruleType="${2}" \
		rule="${3}" \
		val="${4}" \
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
	_log "window ${windowId} ${ruleType} ${rule}:" \
		"setting pointer to (${val})=(${x} ${y})"
	xdotool mousemove --window ${windowId} ${x} ${y} || \
		LogPrio="err" \
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"error setting pointer to (${val})=(${x} ${y})"
}

WindowUndecorate() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		val="${4}" \
		rc=0 \
		state
	state="$(toggle-decorations -s ${windowId})" || \
		return ${OK}
	state="${state##* }"
	_log "window ${windowId} ${ruleType} ${rule}:" \
		"is $([ ${state} -gt 0 ] || echo "un")decorated"
	if [ "${val}" = "${AFFIRMATIVE}" -a ${state} -gt 0 ]; then
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"undecorating"
		toggle-decorations -d ${windowId} || :
	elif [ "${val}" = "${NEGATIVE}" -a ${state} -eq 0 ]; then
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"decorating"
		toggle-decorations -e ${windowId} || :
	fi
}

WindowUnshade() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}"
	IsWindowShaded ${windowId} ||  \
		return ${OK}
	_log "window ${windowId} ${ruleType} ${rule}:" \
		"un-shading"
	wmctrl -i -r ${windowId} -b remove,shade || \
		LogPrio="err" \
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"error un-shading"
}

WindowUnminimize() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}"
	IsWindowMinimized ${windowId} || \
		return ${OK}
	_log "window ${windowId} ${ruleType} ${rule}:" \
		"un-minimizing"
	wmctrl -i -r ${windowId} -b remove,hidden || \
		LogPrio="err" \
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"error un-minimizing"
}

WindowActivate() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}"
	DesktopSetCurrent ${windowId} "${ruleType}" ${rule} \
		$(WindowDesktop ${windowId} "${ruleType}" ${rule}) || :
	WindowUnminimize ${windowId} "${ruleType}" ${rule}
	WindowUnshade ${windowId} "${ruleType}" ${rule}
	[[ $(WindowActive) -eq ${windowId} ]] || \
		xdotool windowactivate ${windowId} || \
			WindowExists ${windowId} || \
				return ${ERR}
	xdotool mousemove --window ${windowId} 0 0 || :
}

WindowTapKeys() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		type="${4}" \
		val="${5}" \
		xkbmap key first
	xkbmap="$(setxkbmap -query | \
		sed -nre '\|^options| s||option|' \
		-e '\|([^:[:blank:]]+)[:[:blank:]]+(.*)| s||-\1 \2|p')"
	setxkbmap us dvorak -rules xorg -model pc105 -option
	case "${type}" in
	text)
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"typing text \"${val}\""
		WindowActivate ${windowId} "${ruleType}" ${rule} || \
			break
		xdotool type --clearmodifiers "${val}" || \
			LogPrio="err" \
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"error typing text"
		;;
	keys)
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"tapping keys \"${val}\""
		first="y"
		for key in $(tr -s '[:blank:]' ' ' <<< "${val}"); do
			[ -n "${first}" ] || \
				sleep 1
			first=""
			WindowActivate ${windowId} "${ruleType}" ${rule} || \
				break
			xdotool key --clearmodifiers "${key}" || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"error tapping keys"
		done
		;;
	esac
	setxkbmap ${xkbmap}
}

WindowTile() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		val="${4}" \
		win x y record recordKey desktop undecorated
	local windowWidth windowHeight windowX windowY windowScreen
	local desktopNum desktopName desktopWidth desktopHeight \
		desktopViewPosX desktopViewPosY \
		desktopWorkareaX desktopWorkareaY desktopWorkareaW desktopWorkareaH

	GetMenuBarHeight ${windowId}
	desktop="$(WindowDesktop ${windowId} "${ruleType}" ${rule})"
	recordKey="tile_${ruleType}${rule}_${desktop}"
	if record="$(awk -v recordKey="${recordKey}" \
	'$1 == recordKey {print $0; rc=-1; exit}
	END{exit rc+1}' < "${VARSFILE}")"; then
		while [ $(wc -w <<< "${record}") -gt 1 ] && \
		win="$(awk 'NF > 1 {print $NF; rc=-1}
		END{exit rc+1}' <<< "${record}")" && \
		[ ${desktop} -ne $(WindowDesktop ${win} ${ruleType} ${rule}) ]; do
			record="$(awk -v s="${SEP}" -v windowId="${win}" \
			'BEGIN{FS=s; OFS=s}
			{for (i=2; i <= NF; i++)
				if ($i == windowId) {
					for (j=i; j < NF; j++)
						$j=$(j+1)
					NF--
					break
				}
			print $0}' <<< "${record}")"
			LogPrio="warn" \
			_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
				"WindowTile: previous tiled window ${win} is not in current desktop"
		done
		if [ $(wc -w <<< "${record}") -gt 1 ]; then
			WindowGeometry ${win} || {
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
					"WindowTile: can't get geometry of previous tiled window ${win}"
				return ${OK}
			}
			LogPrio="debug" \
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"WindowTile: ${record:-${ruleType}${rule}} ${windowId}"
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
			WindowActivate ${windowId} "${ruleType}" ${rule} || :
			undecorated=0
			IsWindowUndecorated ${windowId} || \
				undecorated="${?}"
			[ ${undecorated} -ne 2 ] || \
				return ${ERR}
			[ ${undecorated} -eq 0 ] || \
				let "y-=MenuBarHeight,1"
			_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
				"WindowTile: moving to (${val})=(${x} ${y})"
			xdotool windowmove ${windowId} ${x} ${y} || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
					"WindowTile: can't move to (${val})=(${x} ${y})"
		fi
	else
		_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
			"WindowTile: It's the first window to tile"
	fi
	{ awk -v recordKey="${recordKey}" \
	'$1 != recordKey {print $0}' < "${VARSFILE}"
	printf '%s\n' "${record:-"${recordKey}${SEP}"}${windowId}${SEP}"
	} > "${VARSFILE}.part"
	mv -f "${VARSFILE}.part" "${VARSFILE}"
}

WindowTiling() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		val="${4}"
	_lock_acquire "${VARSFILE}" ${mypid}
	WindowTile ${windowId} "${ruleType}" ${rule} "${val}"
	_lock_release "${VARSFILE}" ${mypid}
}

WindowMosaic() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		val="${4}" \
		win winCount recordKey \
		wW wH w h wX wY m record desktop undecorated \
		maxRows maxCols rows cols row col
	local windowWidth windowHeight windowX windowY windowScreen
	local desktopNum desktopName desktopWidth desktopHeight \
		desktopViewPosX desktopViewPosY \
		desktopWorkareaX desktopWorkareaY desktopWorkareaW desktopWorkareaH

	GetMenuBarHeight ${windowId}
	desktop="$(WindowDesktop ${windowId} "${ruleType}" ${rule})"
	recordKey="mosaic_${ruleType}${rule}_${desktop}"
	if record="$(awk -v recordKey="${recordKey}" \
	'$1 == recordKey {print $0; rc=-1; exit}
	END{exit rc+1}' < "${VARSFILE}")"; then
		m="$(cut -f 1 -s -d "${SEP}" <<< "${record}")${SEP}"
		for win in $(cut -f 2- -s -d "${SEP}" <<< "${record}"); do
			[ ${desktop} -ne $(WindowDesktop ${win} "${ruleType}" ${rule}) ] && \
				LogPrio="warn" \
				_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
					"WindowMosaic: window ${win} is not in current desktop" || \
				m="${m}${win}${SEP}"
		done
		record="${m}"
		let "winCount=$(wc -w <<< "${record}"),1"
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
	_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
		"WindowMosaic: ${cols} columns, ${rows} rows"
	DesktopSize
	col=0
	row=0
	let "wW=(desktopWorkareaW/cols)-5,1"
	let "wH=(desktopWorkareaH/rows)-5,1"
	for win in $(cut -f 2- -s -d "${SEP}" <<< "${record}") ${windowId}; do
		if [ ${col} -eq 0 ]; then
			let "row++,1"
		fi
		let "col++,1"
		let "wX=desktopWorkareaX+(wW+5)*(col-1),1"
		let "wY=desktopWorkareaY+(wH+3)*(row-1),1"
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
			LogPrio="err" \
			_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
				"WindowMosaic: remove,maximized_horz,maximized_vert,minimized"
		_log "window ${win} ${ruleType} ${rule} desktop ${desktop}:" \
			"WindowMosaic: moving to (${wX} ${wY}), resizing to (${w} ${h})"
		wmctrl -i -r ${win} -e "0,${wX},${wY},${w},${h}" || \
				LogPrio="err" \
				_log "window ${win} ${ruleType} ${rule} desktop ${desktop}:" \
					"WindowMosaic: moving to (${wX} ${wY}), resizing to (${w} ${h})"
		if [ ${col} -ge ${cols} ]; then
			col=0
		fi
	done
	{ awk -v recordKey="${recordKey}" \
		'$1 != recordKey {print $0}' < "${VARSFILE}"
	printf '%s\n' "${record:-"${recordKey}${SEP}"}${windowId}${SEP}"
	} > "${VARSFILE}.part"
	mv -f "${VARSFILE}.part" "${VARSFILE}"
}

WindowEnmossay() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		val="${4}"
	_lock_acquire "${VARSFILE}" ${mypid}
	WindowMosaic ${windowId} "${ruleType}" ${rule} "${val}" || :
	_lock_release "${VARSFILE}" ${mypid}
}

WindowPosition() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		val="${4}" \
		x y desktop
	local windowWidth windowHeight windowX windowY windowScreen
	local desktopNum desktopName desktopWidth desktopHeight \
		desktopViewPosX desktopViewPosY \
		desktopWorkareaX desktopWorkareaY desktopWorkareaW desktopWorkareaH

	WindowGeometry ${windowId} || {
		LogPrio="err" \
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"error setting position, can't get window geometry"
		return ${OK}
	}
	desktop="$(WindowDesktop ${windowId} "${ruleType}" ${rule})"
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
	_log "window ${windowId} ${ruleType} ${rule}:" \
		"moving to (${val})=(${x} ${y})"
	xdotool windowmove ${windowId} "${x}" "${y}" || \
		LogPrio="err" \
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"error moving to (${val})=(${x} ${y})"
}

WindowWaitFocus() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		waitForFocus="${4}"
	[[ $(WindowActive) -ne ${windowId} ]] || \
		return ${OK}
	if [ -z "${waitForFocus}" ]; then
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"setting up focus"
		WindowActivate ${windowId} "${ruleType}" ${rule} || :
		return ${OK}
	fi
	LogPrio="info" \
	_log "window ${windowId} ${ruleType} ${rule}:" \
		"waiting to get focus"
	(export windowId LOGFILE Debug BASH_XTRACEFD
	$(CmdWaitFocus ${windowId})) &
	wait ${!} || :
}

WindowSetupRule() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		index action val waitForFocus
	_log "window ${windowId} ${ruleType} ${rule}:" \
		"setting up"

	waitForFocus=""

	while IFS="[= ]" read -r index action val; do
		val="$(_unquote "${val}")"
		! ActionNeedsFocus "${action}" || {
			WindowWaitFocus ${windowId} "${ruleType}" ${rule} "${waitForFocus}"
			waitForFocus=""
		}
		WindowExists ${windowId} || \
			return ${OK}
		case "${action}" in
		set_delay)
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"waiting ${val} seconds to set up"
			waitForFocus="y"
			while [ $((val--)) -ge ${NONE} ]; do
				sleep 1
				WindowExists ${windowId} || \
					break
			done
			;;
		set_focus)
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"setting up focus"
			WindowActivate ${windowId} "${ruleType}" ${rule} || :
			;;
		set_active_desktop)
			if [ ${val} -lt $(DesktopsCount) ]; then
				if [ ${val} -ne $(DesktopCurrent) ]; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"setting up active desktop ${val}"
					xdotool set_desktop ${val} || {
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error setting active desktop ${val}"
					}
				fi
			else
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"can't set invalid active desktop ${val}"
			fi
			;;
		set_desktop)
			[ $(WindowDesktop ${windowId} "${ruleType}" ${rule}) -ge 0 ] || \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"window is pinned to all desktops"
			if [ ${val} -lt $(DesktopsCount) ]; then
				c=0
				while [ $((c++)) -lt 5 ]; do
					[ ${c} -eq 1 ] || \
						sleep 1
					[ ${val} -ne $(WindowDesktop ${windowId} "${ruleType}" ${rule}) ] || \
						break
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"moving window to desktop ${val}"
					xdotool set_desktop_for_window ${windowId} ${val} || \
						break
				done
			fi
			[ ${val} -eq $(WindowDesktop ${windowId} "${ruleType}" ${rule}) ] || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"can't move window to desktop ${val}"
			;;
		set_position)
			WindowPosition ${windowId} "${ruleType}" ${rule} "${val}"
			;;
		set_size)
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"setting size to ${val}"
			xdotool windowsize ${windowId} ${val} || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"error setting size to ${val}"
			;;
		set_tiled)
			WindowTiling ${windowId} "${ruleType}" ${rule} "${val}"
			;;
		set_maximized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximized ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"maximizing"
					wmctrl -i -r ${windowId} -b add,maximized_horz,maximized_vert || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error maximizing"
				}
			else
				! IsWindowMaximized ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"un-maximizing"
					wmctrl -i -r ${windowId} -b remove,maximized_horz,maximized_vert || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error un-maximizing"
				}
			fi
			;;
		set_maximized_horz)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximized_horz ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"maximizing horizontally"
					wmctrl -i -r ${windowId} -b add,maximized_horz || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error maximizing horizontally"
				}
			else
				! IsWindowMaximized_horz ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"un-maximizing horizontally"
					wmctrl -i -r ${windowId} -b remove,maximized_horz || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error un-maximizing horizontally"
				}
			fi
			;;
		set_maximized_vert)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMaximized_vert ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"maximizing vertically"
					wmctrl -i -r ${windowId} -b add,maximized_vert || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error maximizing vertically"
				}
			else
				! IsWindowMaximized_vert ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"un-maximizing vertically "
					wmctrl -i -r ${windowId} -b remove,maximized_vert || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error un-maximizing vertically"
				}
			fi
			;;
		set_fullscreen)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowFullscreen ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"enabling fullscreen"
					wmctrl -i -r ${windowId} -b add,fullscreen || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error enabling fullscreen"
				}
			else
				! IsWindowFullscreen ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"disabling fullscreen"
					wmctrl -i -r ${windowId} -b remove,fullscreen || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error disabling fullscreen"
				}
			fi
			;;
		set_mosaicked)
			WindowEnmossay ${windowId} "${ruleType}" ${rule} "${val}"
			;;
		set_minimized)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowMinimized ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"minimizing"
					xdotool windowminimize ${windowId} || \
					LogPrio="err" \
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"error minimizing"
				}
			else
				WindowUnminimize ${windowId} "${ruleType}" ${rule}
			fi
			;;
		set_shaded)
			rc=0
			IsWindowShaded ${windowId} || \
				rc=${?}
			if [ "${val}" = "${AFFIRMATIVE}"  -a \
			\( ${rc} -eq 1 -o ${rc} -eq 2 \) ]; then
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"shading"
				wmctrl -i -r ${windowId} -b add,shade || \
					LogPrio="err" \
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"error shading"
			elif [ "${val}" = "${NEGATIVE}"  -a \
			\( ${rc} -eq 0 -o ${rc} -eq 2 \) ]; then
				WindowUnshade ${windowId} "${ruleType}" ${rule}
			fi
			;;
		set_undecorated)
			WindowUndecorate ${windowId} "${ruleType}" ${rule} "${val}"
			;;
		set_sticky)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				IsWindowSticky ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"sticking"
					wmctrl -i -r ${windowId} -b add,sticky || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error sticking"
				}
			else
				! IsWindowSticky ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"un-sticking"
					wmctrl -i -r ${windowId} -b remove,sticky || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error un-sticking"
				}
			fi
			;;
		set_above)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowBelow ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"disabling below"
					wmctrl -i -r ${windowId} -b remove,below || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error disabling below"
				}
				IsWindowAbove ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"enabling above"
					wmctrl -i -r ${windowId} -b add,above || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error enabling above"
				}
			else
				! IsWindowAbove ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"disabling above"
					wmctrl -i -r ${windowId} -b remove,above || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error disabling above"
				}
			fi
			;;
		set_below)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				! IsWindowAbove ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"disabling above"
					wmctrl -i -r ${windowId} -b remove,above || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error disabling above"
				}
				IsWindowBelow ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"enabling below"
					wmctrl -i -r ${windowId} -b add,below || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error enabling below"
				}
			else
				! IsWindowBelow ${windowId} || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"disabling below"
					wmctrl -i -r ${windowId} -b remove,below || \
						LogPrio="err" \
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"error disabling below"
				}
			fi
			;;
		set_pinned)
			if [ "${val}" = "${AFFIRMATIVE}" ]; then
				[ $(WindowDesktop ${windowId} "${ruleType}" ${rule}) -eq -1 ] || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"pinning to all desktops"
					xdotool set_desktop_for_window ${windowId} "-1"
				}
			else
				[ $(WindowDesktop ${windowId} "${ruleType}" ${rule}) -ne -1 ] || {
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"un-pinning to all desktops"
					xdotool set_desktop_for_window $(DesktopCurrent)
				}
			fi
			;;
		set_closed)
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"closing window"
			xdotool windowclose ${windowId} || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"error closing window"
			;;
		set_killed)
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"killing window"
			xdotool windowkill ${windowId} || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"error killing window"
			;;
		set_pointer)
			PointerMove ${windowId} "${ruleType}" ${rule} "${val}"
			;;
		set_tap_keys)
			WindowTapKeys ${windowId} "${ruleType}" ${rule} "keys" "${val}"
			;;
		set_type_text)
			WindowTapKeys ${windowId} "${ruleType}" ${rule} "text" "${val}"
			;;
		*)
			LogPrio="err" \
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"invalid action ${action}='${val}'"
			;;
		esac
	done < <(sort --numeric --key 1,1 \
		< <(sed -nre "\|^${ruleType}${rule}_([[:digit:]]+)_(set_.*)|s||\1 \2|p" \
		< <(set)))

	_log "window ${windowId} ${ruleType} ${rule}:" \
		"end setting up"
}

WindowSetup() {
	local windowId="${1}" \
		setupGlobalRules="${2}" \
		setupRules="${3}" \
		rule mypid rc=${OK}

	mypid="$(($(ps -o ppid= -C "ps -o ppid= -C ps -o ppid=")))"

	if [ -n "${setupGlobalRules}" ]; then
		_log "window ${windowId}: applying global rules" \
			"( $(tr -s '[:blank:],' ',' < <(echo ${setupGlobalRules})) )"
		for rule in ${setupGlobalRules}; do
			WindowSetupRule ${windowId} "globalrule" ${rule} || {
				LogPrio="err" \
				_log "window ${windowId} globalrule ${rule}:" \
					"error setting global rule"
				rc=${ERR}
				break
			}
		done
		_log "window ${windowId}: end applying global rules" \
			"( $(tr -s '[:blank:],' ',' < <(echo ${setupGlobalRules})) )"
	fi
	if  [ ${rc} -eq ${OK} -a -n "${setupRules}" ]; then
		_log "window ${windowId}: applying rules" \
			"( $(tr -s '[:blank:],' ',' < <(echo ${setupRules})) )"
		for rule in ${setupRules}; do
			WindowSetupRule ${windowId} "rule" ${rule} || {
				LogPrio="err" \
				_log "window ${windowId} rule ${rule}:" \
					"error setting rule"
				break
			}
		done
		_log "window ${windowId}: end applying rules" \
			"( $(tr -s '[:blank:],' ',' < <(echo ${setupRules})) )"
	fi
}

WindowSelect() {
	local ruleType="${1}" \
		rules rule
	rule=${NONE}
	rules="$([ "${ruleType}" = "rule" ] && echo ${Rules} || echo ${GlobalRules})"
	while [ $((rule++)) -lt ${rules} ]; do
		rc="${AFFIRMATIVE}"
		selectNoactions=""
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"checking"
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
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"title \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"title \"${deselected}${val}\""
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
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"state \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"state \"${deselected}${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_type)
				if grep -qs -iwEe "${val}" <<< "$(WindowType ${windowId})" ; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"type \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"type \"${deselected}${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_app_name)
				if [ "${val}" = "$(WindowAppName ${windowId})" ]; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"app name \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"app name \"${deselected}${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_application)
				if grep -qs -iwF "${val}" \
				<<< "$(WindowApplication ${windowId} 2> /dev/null)" ; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"application \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"application \"${deselected}${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_class)
				if grep -qs -iwEe "${val}" <<< "$(WindowClass ${windowId})" ; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"class \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"class \"${deselected}${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_role)
				if grep -qs -iwF "${val}" <<< "$(WindowRole ${windowId})"; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"role \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"role \"${deselected}${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_desktop)
				if [ "${val}" = "$(WindowDesktop ${windowId} "${ruleType}" ${rule})" ]; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"desktop \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"desktop \"${deselected}${val}\""
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
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"${propName} is \"${deselected}${val}\""
					else
						_log "window ${windowId} ${ruleType} ${rule}:" \
							"${propName} is not \"${deselected}${val}\""
						rc=""
					fi
					;;
				*)
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${propName} has an invalid state"
					rc=""
					;;
				esac
				;;
			select_desktop_size)
				DesktopSize $(WindowDesktop ${windowId} "${ruleType}" ${rule})
				if [ "${val}" = "${desktopWidth}x${desktopHeight}" ]; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"desktop size \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"desktop size \"${deselected}${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_desktop_workarea)
				if [ "${val}" = \
				"${desktopWorkareaX},${desktopWorkareaY} ${desktopWorkareaW}x${desktopWorkareaH}" \
				]; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"desktop workarea \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"desktop workarea \"${deselected}${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_desktops)
				if [ "${val}" = "$(DesktopsCount)" ]; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"desktops count \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"desktopsCount \"${deselected}${val}\""
					[ -n "${deselected}" ] || \
						rc=""
				fi
				;;
			select_stop)
				selectStop="y"
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"enabling \"select stop\""
				;;
			select_noactions)
				selectNoactions="y"
				LogPrio="debug" \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"enabling \"select noactions\""
				;;
			*)
				LogPrio="err" \
				_log "${ruleType} ${rule}:" \
					"invalid property \"${prop}\" \"${deselected}${val}\""
				rc=""
				;;
			esac
		done < <(sort --numeric --key 1,1 \
		< <(sed -nre "\|^${ruleType}${rule}_([[:digit:]]+)_(select_.*)|s||\1 \2|p" \
		< <(set)))

		if [ -n "${rc}" ]; then
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"end check, this ${ruleType} is selected"
			if [ -n "${selectNoactions}" ]; then
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"${ruleType} without actions to setup"
			else
				case "${ruleType}" in
				rule)
					setupRules="${setupRules}${rule}${TAB}"
					;;
				globalrule)
					setupGlobalRules="${setupGlobalRules}${rule}${TAB}"
					;;
				esac
			fi
			[ -z "${selectStop}" ] || \
				break
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"continue checking other ${ruleType}s"
		else
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"end check, does not match"
			selectStop=""
		fi
	done
}

WindowNew() {
	local windowId="${1}" \
		rule setupRules setupGlobalRules \
		propName netState \
		index prop val deselected \
		rc selectStop selectNoactions
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
	# we'll set up only the first rule that match,
	# unless that this rule contains the command "select others"
	setupRules=""
	setupGlobalRules=""
	selectStop=""
	WindowSelect "globalrule"
	[ -n "${selectStop}" ] || \
		WindowSelect "rule"
	if [ -n "${setupGlobalRules}" -o -n "${setupRules}" ]; then
		(WindowSetup ${windowId} "${setupGlobalRules}" "${setupRules}") &
	else
		_log "window ${windowId}: There is not any rule to setup"
	fi
	return ${OK}
}

WindowsUpdate() {
	local windowId window_type pids
	_log "current window count ${#}"
	for windowId in $(grep -svwF "$(printf '%s\n' ${WindowIds})" \
	< <(printf '%s\n' "${@}")); do
		WindowNew ${windowId} || :
	done

	for windowId in $(grep -svwF "$(printf '%s\n' "${@}")" \
	< <(printf '%s\n' ${WindowIds})); do
		_log "window ${windowId}: has been closed"
		if pids="$(ps -C "$(CmdWaitFocus ${windowId})" -o pid= -o user= | \
		awk -v user="${USER}" \
		'$2 == user && $1 ~ "^[[:digit:]]+$" {printf $1 " "; rc=-1}
		END{exit rc+1}')"; then
			kill ${pids} 2> /dev/null || :
		fi
		_lock_acquire "${VARSFILE}" ${$}
		if grep -qswF "${windowId}" < "${VARSFILE}"; then
			LogPrio="debug" \
				_log "window ${windowId}: Tile info:" \
					"$(grep -swF "${windowId}" < "${VARSFILE}")"
			awk -v s="${SEP}" -v windowId="${windowId}" \
			'BEGIN{FS=s; OFS=s}
			{for (i=2; i <= NF; i++)
				if ($i == windowId) {
					for (j=i; j < NF; j++)
						$j=$(j+1)
					NF--
					break
				}
			print $0}' < "${VARSFILE}" > "${VARSFILE}.part"
			mv -f "${VARSFILE}.part" "${VARSFILE}"
		fi
		_lock_release "${VARSFILE}" ${$}
	done

	WindowIds="${@}"
	return ${OK}
}

Main() {
	# internal variables, daemon scope
	local Rules GlobalRules Debug="" EmptyList LogPrio txt \
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
	APPNAME="desktoparrange"
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
		echo "error: ${APPNAME} is already running for this session" >&2
		exit ${ERR}
	fi
	if [ $(ps -o ppid= ${$}) -eq 1 ]; then
		shift
		echo "info: ${APPNAME} start ${@}" >&2
		Main "${@}"
	else
		echo "info: submit ${APPNAME} ${@}" >&2
		((exec "${0}" "${@}" > /dev/null 2>&1) &)
	fi
	;;
stop)
	if ! pid="$(AlreadyRunning)"; then
		echo "error: ${APPNAME} is not running for this session" >&2
		exit ${ERR}
	fi
	echo "info: ${APPNAME} stop" >&2
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
		echo "error: ${APPNAME} is not running for this session" >&2
		exit ${ERR}
	fi
	echo "info: ${APPNAME} reload" >&2
	kill -s HUP ${pid} 2> /dev/null
	;;
status)
	if pid="$(AlreadyRunning)"; then
		echo "info: log files" \
			$(ls -Q "${LOGFILE}"{,.xtrace} 2> /dev/null) >&2
	else
		echo "info: ${APPNAME} is not running for this session" >&2
		exit ${ERR}
	fi
	;;
*)
	echo "wrong action." >&2
	echo "valid actions are: start|stop|restart|reload|status" >&2
	exit ${ERR}
	;;
esac
: