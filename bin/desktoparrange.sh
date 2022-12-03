#!/bin/bash

#************************************************************************
#  DesktopArrange
#
#  Arrange Linux worskpaces
#  according to a set of configurable rules.
#
#  $Revision: 0.40 $
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
	_lock_acquire "${VARSFILE}" ${mypid}
	MenuBarHeight="$(awk -v var="MenuBarHeight" -F '=' \
		'$1 == var {print $2; exit}' < "${VARSFILE}")"
	_lock_release "${VARSFILE}" ${mypid}
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
	_lock_acquire "${VARSFILE}" ${mypid}
	awk -v var="MenuBarHeight" -F '=' \
	'$1 == var {rc=-1; exit}
	END{exit rc+1}' < "${VARSFILE}" || {
		echo "MenuBarHeight=${MenuBarHeight}" >> "${VARSFILE}"
		echo "MenuBarHeight=${MenuBarHeight}" >> "${PIPE}"
	}
	_lock_release "${VARSFILE}" ${mypid}
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

PrintWindowInfo() {
	local windowId="${1}"

	DesktopSize $(WindowDesktop ${windowId})

	printf "%s='%s'\n" \
		"Window id" ${windowId} \
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
}

WindowShow() {
	local windowId="${1}"
	wmctrl -i -r ${windowId} -b remove,maximized_horz,maximized_vert && \
	wmctrl -i -r ${windowId} -b remove,shaded,hidden && \
	wmctrl -i -r ${windowId} -b remove,above,below && \
	wmctrl -i -r ${windowId} -b remove,fullscreen || \
		LogPrio="err" \
		_log "window ${windowId}:" \
			"Can't remove,maximized_horz,maximized_vert,shaded,hidden,above,below,fullscreen"
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

WindowWaitFocus() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		waitForFocus="${4:-}"
	sleep 0.1
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

	WindowShow ${windowId}
	WindowGeometry ${windowId} || {
		LogPrio="err" \
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"error setting position, can't get window geometry"
		return ${OK}
	}
	desktop="$(WindowDesktop ${windowId} "${ruleType}" ${rule})"
	DesktopSize ${desktop}

	GetMenuBarHeight ${windowId}

	x="$(cut -f 1 -s -d ' ' <<< "${val}")"
	if [ "${x}" = "${x//[^-0-9]}" ]; then
		if [ ${x} -lt ${desktopWorkareaX} ]; then
			x="left"
		elif [ ${x} -ge $((desktopWorkareaX+desktopWorkareaW-windowWidth)) ]; then
			x="right"
		fi
	fi
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
	if [ "${y}" = "${y//[^-0-9]}" ]; then
		if [ ${y} -lt ${desktopWorkareaY} ]; then
			y="top"
		elif [ ${y} -ge $((desktopWorkareaY+desktopWorkareaH-windowHeight)) ]; then
			y="bottom"
		fi
	fi
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
	xdotool mousemove --window ${windowId} $((windowWidth/2)) $((windowHeight/2)) || \
		LogPrio="err" \
		_log "window ${windowId} ${ruleType} ${rule}:" \
			"error setting pointer to ($((windowWidth/2)) $((windowHeight/2)))"
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

	WindowShow ${windowId}
	GetMenuBarHeight ${windowId}
	desktop="$(WindowDesktop ${windowId} "${ruleType}" ${rule})"
	recordKey="Tile_${ruleType}_${rule}_${desktop}"
	_lock_acquire "${VARSFILE}" ${mypid}
	record="$(awk -v recordKey="${recordKey}" \
	'$1 == recordKey {print $0; exit}' < "${VARSFILE}")"
	_lock_release "${VARSFILE}" ${mypid}
	if [ -n "${record}" ]; then
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
			WindowShow ${win}
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
			x="$(cut -f 3 -s -d ' ' <<< "${val}")"
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
			y="$(cut -f 4 -s -d ' ' <<< "${val}")"
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
				"WindowTile: tiling to" \
				"($(cut -f 3- -s -d ' ' <<< "${val}"))=(${x} ${y})"
			xdotool windowmove ${windowId} ${x} ${y} || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
					"WindowTile: can't tile to" \
					"($(cut -f 3- -s -d ' ' <<< "${val}"))=(${x} ${y})"
			xdotool mousemove --window ${windowId} $((windowWidth/2)) $((windowHeight/2)) || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
					"error setting pointer to ($((windowWidth/2)) $((windowHeight/2)))"
		fi
	fi
	if [ $(wc -w <<< "${record}") -le 1 ]; then
		_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
			"WindowTile: It's the first window to tile"
		WindowPosition ${windowId} "${ruleType}" ${rule} \
			"$(cut -f -2 -s -d ' ' <<< "${val}")"
	fi
	_lock_acquire "${VARSFILE}" ${mypid}
	{ awk -v recordKey="${recordKey}" \
	'$1 != recordKey {print $0}' < "${VARSFILE}"
	printf '%s\n' "${record:-"${recordKey}${SEP}"}${windowId}${SEP}"
	} > "${VARSFILE}.part"
	mv -f "${VARSFILE}.part" "${VARSFILE}"
	_lock_release "${VARSFILE}" ${mypid}
}

WindowTiling() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		val="${4}"
	WindowTile ${windowId} "${ruleType}" ${rule} "${val}"
}

GroupEnmossay() {
	local record="${1}" \
		windowIds windowId action pid ruleType rule val \
		wW wH w h wX wY m record desktop undecorated \
		numRows numCols maxRows maxCols rows cols row col
	local windowWidth windowHeight windowX windowY windowScreen
	local desktopNum desktopName desktopWidth desktopHeight \
		desktopViewPosX desktopViewPosY \
		desktopWorkareaX desktopWorkareaY desktopWorkareaW desktopWorkareaH

	action="$(cut -f 1 -s -d '_' <<< "${record}")"
	pid="$(cut -f 2 -s -d '_' <<< "${record}")"
	ruleType="$(cut -f 3 -s -d '_' <<< "${record}")"
	rule="$(cut -f 4 -s -d '_' <<< "${record}")"
	desktop="$(cut -f 5 -s -d '_' <<< "${record}")"
	val="$(cut -f 2 -s -d "${SEP}" <<< "${record}")"
	windowIds=""

	windowIds=""
	winCount=0
	for windowId in $(cut -f 3- -s -d "${SEP}" <<< "${record}"); do
		if [ ${desktop} -ne $(WindowDesktop ${windowId} "${ruleType}" ${rule}) ]; then
			LogPrio="warn" \
			_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
				"GroupEnmossay: window ${windowId} is not in current desktop"
			continue
		fi
		GetMenuBarHeight ${windowId}
		windowIds="${windowIds}${windowId}${SEP}"
		let "winCount++,1"
	done
	[ ${winCount} -gt 0 ] || {
		LogPrio="err" \
		_log "GroupEnmossay ${ruleType} ${rule} desktop ${desktop}:" \
			"no windows to setup"
		return ${OK}
	}
	if [ ${winCount} -eq 1 ]; then
		windowId="$(cut -f 1 -s -d "${SEP}" <<< "${windowIds}")"
		_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
			"GroupEnmossay: maximizing"
		WindowWaitFocus ${windowId} "${ruleType}" ${rule}
		WindowShow ${windowId}
		wmctrl -i -r ${windowId} -b add,maximized_horz,maximized_vert || \
			LogPrio="err" \
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"error maximizing"
		return ${OK}
	fi
	numRows="$(cut -f 1 -s -d ' ' <<< "${val}")"
	numCols="$(cut -f 2 -s -d ' ' <<< "${val}")"
	maxRows="$(cut -f 3 -s -d ' ' <<< "${val}")"
	maxCols="$(cut -f 4 -s -d ' ' <<< "${val}")"
	rows=0
	cols=0
	if [ ${numCols} -gt 0 ]; then
		let "rows=winCount%numCols == 0 ? winCount/numCols : (winCount/numCols)+1,1"
		[ ${maxRows} -eq 0 -o ${rows} -le ${maxRows} ] || \
			rows=${maxRows}
		let "cols=winCount%rows == 0 ? winCount/rows : (winCount/rows)+1,1"
	elif [ ${numRows} -gt 0 ]; then
		let "cols=winCount%numRows == 0 ? winCount/numRows : (winCount/numRows)+1,1"
		[ ${maxCols} -eq 0 -o ${cols} -le ${maxCols} ] || \
			cols=${maxCols}
		let "rows=winCount%cols == 0 ? winCount/cols : (winCount/cols)+1,1"
	else
		i=1
		while [ $((j = winCount%i == 0 ? winCount/i : (winCount+(i/2))/i)) -gt ${i} ] || \
		[ $((j*i)) -lt ${winCount} ]; do
			let "i++,1"
		done
		if [ ${numCols} -lt 0 ]; then
			rows=${i}
			cols=${j}
		else
			rows=${j}
			cols=${i}
		fi
	fi
	_log "${action} ${ruleType} ${rule} desktop ${desktop}:" \
		"GroupMosaic: ${cols} columns, ${rows} rows"
	DesktopSize
	col=0
	row=0
	let "wW=(desktopWorkareaW/cols)-5,1"
	let "wH=(desktopWorkareaH/rows)-5,1"
	for windowId in ${windowIds}; do
		if [ ${col} -eq 0 ]; then
			let "row++,1"
		fi
		let "col++,1"
		let "wX=desktopWorkareaX+(wW+5)*(col-1),1"
		let "wY=desktopWorkareaY+(wH+3)*(row-1),1"
		undecorated=0
		IsWindowUndecorated ${windowId} || \
			undecorated="${?}"
		[ ${undecorated} -ne 2 ] || \
			continue
		w="${wW}"
		[ ${undecorated} -ne 0 ] && \
			let "h=wH-(MenuBarHeight/2),1" || \
			h=${wH}
		WindowWaitFocus ${windowId} "${ruleType}" ${rule}
		WindowShow ${windowId}
		if [ ${rows} -eq 1 ]; then
			wY=-1 h=-1
			_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
				"GroupEnmossay: moving to (${wX} ${wY}), resizing to (${w} ${h})"
			wmctrl -i -r ${windowId} -e "0,${wX},${wY},${w},${h}" || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
					"GroupEnmossay: moving to (${wX} ${wY}), resizing to (${w} ${h})"
			_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
				"GroupEnmossay: maximizing vert"
			WindowWaitFocus ${windowId} "${ruleType}" ${rule}
			wmctrl -i -r ${windowId} -b add,maximized_vert || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"error maximizing vert"
		elif [ ${cols} -eq 1 ]; then
			wX=-1; w=-1
			_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
				"GroupEnmossay: moving to (${wX} ${wY}), resizing to (${w} ${h})"
			wmctrl -i -r ${windowId} -e "0,${wX},${wY},${w},${h}" || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
					"GroupEnmossay: moving to (${wX} ${wY}), resizing to (${w} ${h})"
			_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
				"GroupEnmossay: maximizing horz"
			WindowWaitFocus ${windowId} "${ruleType}" ${rule}
			wmctrl -i -r ${windowId} -b add,maximized_horz || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule}:" \
					"error maximizing horz"
		else
			_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
				"GroupEnmossay: moving to (${wX} ${wY}), resizing to (${w} ${h})"
			wmctrl -i -r ${windowId} -e "0,${wX},${wY},${w},${h}" || \
					LogPrio="err" \
					_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
						"GroupEnmossay: moving to (${wX} ${wY}), resizing to (${w} ${h})"
		fi
		if WindowGeometry ${windowId}; then
			xdotool mousemove --window ${windowId} $((windowWidth/2)) $((windowHeight/2)) || \
				LogPrio="err" \
				_log "window ${windowId} ${ruleType} ${rule} desktop ${desktop}:" \
					"error setting pointer to ($((windowWidth/2)) $((windowHeight/2)))"
		else
			LogPrio="err" \
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"error setting position, can't get window geometry"
			return ${OK}
		fi
		if [ ${col} -ge ${cols} ]; then
			col=0
		fi
	done
}

WindowSetupRule() {
	local windowId="${1}" \
		ruleType="${2}" \
		rule="${3}" \
		index action val waitForFocus desktop record recordKey
	_log "window ${windowId} ${ruleType} ${rule}:" \
		"setting up"

	waitForFocus=""
	desktop="$(WindowDesktop ${windowId} "${ruleType}" ${rule})"

	while IFS="[= ]" read -r index action val; do
		val="$(_unquote "${val}")"
		[ "${action}" = "set_mosaicked" ] || \
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
			recordKey="Mosaic_${pidWindowsArrange}_${ruleType}_${rule}_${desktop}"
			_lock_acquire "${VARSFILE}" ${mypid}
			if record="$(awk -v recordKey="${recordKey}" \
			'$1 == recordKey {print $0; rc=-1; exit}
			END{exit rc+1}' < "${VARSFILE}")"; then
				[ "${val}" = "$(cut -f 2 -s -d "${SEP}" <<< "${record}")" ] || \
					LogPrio="err" \
					_log "${ruleType} ${rule}:" \
						"have defined multiple Mosaic values (${val})"
			else
				record="${recordKey}${SEP}${val}${SEP}"
			fi
			{	awk -v recordKey="${recordKey}" \
				'$1 != recordKey {print $0}' < "${VARSFILE}"
				printf '%s\n' "${record}${windowId}${SEP}"
			} > "${VARSFILE}.part"
			mv -f "${VARSFILE}.part" "${VARSFILE}"
			_lock_release "${VARSFILE}" ${mypid}
			_log "window ${windowId} ${ruleType} ${rule}:" \
				"mosaic pending"
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
		setupTempRules="${4}" \
		mypid="${5:-}" \
		rule rc=${OK}

	if [ -z "${mypid}" ]; then
		while mypid="$(ps -o ppid= -C "ps -o ppid= -C ps -o ppid=")";
		[ $(wc -w <<< "${mypid}") -ne 1 ]; do
			sleep .1
		done
		mypid=$((mypid))
	fi

	if [ -n "${setupGlobalRules}" ]; then
		_log "window ${windowId}: applying global rules" \
			"( $(tr -s '[:blank:],' ',' < <(echo ${setupGlobalRules})) )"
		for rule in ${setupGlobalRules}; do
			WindowSetupRule ${windowId} "Globalrule" ${rule} || {
				LogPrio="err" \
				_log "window ${windowId} Globalrule ${rule}:" \
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
			WindowSetupRule ${windowId} "Rule" ${rule} || {
				LogPrio="err" \
				_log "window ${windowId} Rule ${rule}:" \
					"error setting rule"
				rc=${ERR}
				break
			}
		done
		_log "window ${windowId}: end applying rules" \
			"( $(tr -s '[:blank:],' ',' < <(echo ${setupRules})) )"
	fi
	if  [ ${rc} -eq ${OK} -a -n "${setupTempRules}" ]; then
		_log "window ${windowId}: applying temporary rule ${setupTempRules}"
		WindowSetupRule ${windowId} "Temprule" ${setupTempRules} || {
			LogPrio="err" \
			_log "window ${windowId} Temprule ${setupTempRules}:" \
				"error setting rule"
			rc=${ERR}
		}
		_log "window ${windowId}: end applying temporary rule ${setupTempRules}"
	fi
	return ${rc}
}

WindowSelect() {
	local windowId="${1}" \
		ruleType="${2}" \
		checkRules="${3:-}" \
		rules rule propName netState \
		index prop val val1 \
		deselected selectNoactions selectActions rc action

	[ -n "${checkRules}" ] || \
		checkRules="$(echo \
			$(seq 1 "$( \
				[ "${ruleType}" = "Rule" ] \
				&& echo ${Rules} \
				|| echo ${GlobalRules})"))"

	for rule in ${checkRules}; do
		rc="${AFFIRMATIVE}"
		selectNoactions=""
		selectActions=""
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
			if [ "${prop}" = "select_name" ]; then
				deselected=""
				[ "${val:0:1}" != "!" ] || {
					deselected="!"
					val="${val:1}"
				}
				if grep -qs -iEe "${val}" <<< "$(WindowTitle ${windowId})"; then
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"${deselected:+"does not "}match" \
						"name \"${deselected}${val}\""
					[ -z "${deselected}" ] || \
						rc=""
				else
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"$([ -n "${deselected}" ] || echo "does not ")match" \
						"name \"${deselected}${val}\""
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
				if [ "${val}" = "${val//[^0-9]}" ]; then
					val1="${val}"
				elif [ "${val}" = "current" ]; then
					val1="$(DesktopCurrent)"
				else
					LogPrio="err" \
					_log "window ${windowId} ${ruleType} ${rule}:" \
						"can't select invalid desktop \"${val}\""
					continue
				fi
				if [ ${val1} -eq $(WindowDesktop ${windowId} "${ruleType}" ${rule}) ]; then
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
			select_actions)
				selectActions="${val}"
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
				Rule)
					setupRules="${setupRules}${rule}${TAB}"
					;;
				Globalrule)
					setupGlobalRules="${setupGlobalRules}${rule}${TAB}"
					;;
				Temprule)
					setupTempRules="${setupTempRules}${rule}${TAB}"
					;;
				*)
					LogPrio="err" \
					_log "WindowSelect: window ${windowId} ${ruleType} ${rule}:" \
					"invalid ruleType"
					;;
				esac
				for action in ${selectActions}; do
					[ "${actionsRule}" != "${actionsRule//${action}/}" ] || \
						actionsRule="${actionsRule}${action}${SEP}"
				done
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

WindowArrange() {
	local windowId="${1}" \
		checkGlobalRules="${2}" \
		checkRules="${3}" \
		checkTempRules="${4:-}" \
		setupRules setupGlobalRules setupTempRules \
		selectStop
	local desktopNum desktopName desktopWidth desktopHeight \
		desktopViewPosX desktopViewPosY \
		desktopWorkareaX desktopWorkareaY desktopWorkareaW desktopWorkareaH

	[ -z "${WindowInfo}" ] || \
		PrintWindowInfo ${windowId} >> "${LOGFILE}"

	# checking properties of this window
	# we'll set up only the first rule that match,
	# unless that this rule contains the command "select others"
	setupGlobalRules=""
	setupRules=""
	setupTempRules=""
	selectStop=""
	[ -z "${checkGlobalRules}" ] || \
		WindowSelect ${windowId} "Globalrule"
	[ -z "${checkRules}" ] || \
		[ -n "${selectStop}" ] || \
			WindowSelect ${windowId} "Rule"
	[ -z "${checkTempRules}" ] || \
		[ -n "${selectStop}" ] || \
			WindowSelect ${windowId} "Temprule" "${checkTempRules}"
	if [ -n "${setupGlobalRules}" -o -n "${setupRules}" -o -n "${setupTempRules}" ]; then
		if [ "${actionsRule}" = "${actionsRule//tiled/}" ]; then
			WindowSetup ${windowId} \
				"${setupGlobalRules}" "${setupRules}" "${setupTempRules}" &
		else
			WindowSetup ${windowId} \
				"${setupGlobalRules}" "${setupRules}" "${setupTempRules}" ${mypid}
		fi
	else
		_log "window ${windowId}: there is nothing to do"
		return ${ERR}
	fi
}

WindowsArrange() {
	local windowIds="${1}" \
		checkGlobalRules="${2}" \
		checkRules="${3}" \
		checkTempRules="${4:-}" \
		windowId mypid pidWindowsArrange pid pidsChildren \
		record records actionsRule

	while mypid="$(ps -o ppid= -C "ps -o ppid= -C ps -o ppid=")";
	[ $(wc -w <<< "${mypid}") -ne 1 ]; do
		sleep .1
	done
	mypid=$((mypid))
	pidWindowsArrange="${mypid}"

	actionsRule=""
	for windowId in ${windowIds}; do
		if pid="$(_lock_active "${LOGDIR}${windowId}")"; then
			LogPrio="err" \
			_log "WindowsArrange: window ${windowId}: is locked by process ${pid}"
			continue
		fi
		_lock_acquire "${LOGDIR}${windowId}" ${mypid}
		WindowArrange ${windowId} \
		"${checkGlobalRules}" "${checkRules}" "${checkTempRules}" || \
			_lock_release "${LOGDIR}${windowId}" ${mypid}
	done

	pidsChildren=""; _ps_children ${mypid};
	while pidsChildren="$(_pids_active ${pidsChildren})"; do
		wait ${pidsChildren} || :
	done

	if [ "${actionsRule}" != "${actionsRule//mosaicked/}" ]; then
		_lock_acquire "${VARSFILE}" ${mypid}
		records="$(awk -v recordKey="Mosaic_${mypid}_" \
			'$1 ~ recordKey {print $0}' < "${VARSFILE}")"
		_lock_release "${VARSFILE}" ${mypid}
		while read -r record; do
			GroupEnmossay "${record}"
		done <<< "${records}"
	fi

	for windowId in ${windowIds}; do
		if [ "$(_lock_active "${LOGDIR}${windowId}")" = ${mypid} ]; then
			_lock_release "${LOGDIR}${windowId}" ${mypid}
		fi
	done

	if [ -n "${checkTempRules}" ]; then
		_lock_acquire "${VARSFILE}" ${mypid}
		sed -i -e "\|_Temprule_${checkTempRules}_|d" "${VARSFILE}"
		_lock_release "${VARSFILE}" ${mypid}
	fi
}

WindowsUpdate() {
	local windowId pids
	_log "current window count ${#}"

	! windowId="$(grep -svwF "$(printf '%s\n' ${WindowIds})" \
	< <(printf '%s\n' "${@}"))" || \
		WindowsArrange "${windowId}" "Globalrule" "Rule" &

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

TempRuleLine() {
	[ -n "${line}" ] || \
		return ${OK}

	if [ -z "${rule}" ]; then
		_lock_acquire "${VARSFILE}" ${$}
		if rule="$(awk \
		-v var="${ruleType}" -F '=' \
		'$1 == var {print ++$2; rc=-1; exit}
		END{exit rc+1}' < "${VARSFILE}")"; then
			sed -i -e "\|^${ruleType}=.*|s||${ruleType}=${rule}|" "${VARSFILE}"
		else
			rule=1
			echo "${ruleType}=${rule}" >> "${VARSFILE}"
		fi
		_lock_release "${VARSFILE}" ${$}
	fi
	grep -swEe '^(select|deselect|set|unset)' <<< "${line}" && \
	RuleLine "${ruleType}" "${rule}" "${line}" || {
		msg="DesktopArrange: invalid command: \"${line}\""
		LogPrio="err" \
		_log "${msg}"
		return ${ERR}
	}
	line=""
}

CheckTempRule() {
	local cmd="${1}" \
		ruleType="Temprule" \
		indexTempruleSet indexTempruleSelect actionsRule \
		line ParmsArray i

	rule=""
	msg=""
	indexTempruleSelect=0
	indexTempruleSet=0
	actionsRule=""

	declare -A ParmsArray
	eval ParmsArray=(${cmd})
	line=""
	for i in $(seq 1 $((${#ParmsArray[@]}-1)) ); do
		if [ "${ParmsArray[${i}]}" = ":" ]; then
			TempRuleLine || \
				return ${OK}
		elif [ -n "${ParmsArray[${i}]}" ]; then
			line="${line:+"${line} "}${ParmsArray[${i}]}"
		fi
	done
	TempRuleLine || \
		return ${OK}
	
	if [ -n "${rule}" ]; then
		[ -z "${actionsRule}" ] || \
			eval Temprule${rule}_0_select_actions=\'${actionsRule}\'
	else
		msg="DesktopArrange: line does not contain any command"
	fi
}

DesktopArrange() {
	local cmd="${1}" \
		rule msg \
		winIds

	LogPrio="debug" \
	_log "DesktopArrange: received command \"${cmd}\""

	CheckTempRule "${cmd}"
	[ -n "${rule}" -a -z "${msg}" ] || {
		LogPrio="warn" \
		_log "${msg:-"DesktopArrange: line does not contain any command"}"
		return ${OK}
	}

	case "${cmd}" in
	\[0\]=\"desktoparrange\"\ \[*)
		winIds="$(wmctrl -l | \
			awk -v desktop="$(DesktopCurrent)" \
			'BEGIN{ORS="\t"}
			$2 == desktop {print $1; rc=-1}
			END{exit rc+1}')" || {
				LogPrio="err" \
				_log "DesktopArrange: no windows in current desktop"
				return ${OK}
			}
		;;
	\[0\]=\"execute\"\ \[*)
		winIds="$(wmctrl -l | \
			awk \
			'BEGIN{ORS="\t"}
			$2 != -1 {print $1; rc=-1}
			END{exit rc+1}')" || {
				LogPrio="err" \
				_log "DesktopArrange: no windows"
				return ${OK}
			}
		;;
	*)
		LogPrio="err" \
		_log "DesktopArrange: invalid command \"${cmd}\""
		return ${OK}
		;;
	esac

	winIds="$(xprop -root "_NET_CLIENT_LIST_STACKING" | \
		cut -f 2- -s -d '#' | \
		tr -s '[:space:],' '\n' | \
		grep -swF "$(printf '0x%0x\n' ${winIds})")" || {
			LogPrio="err" \
			_log "DesktopArrange: no windows in stack"
			return ${OK}
		}

	WindowsArrange "${winIds}" "Globalrule" "" ${rule} &
}

Main() {
	# internal variables, daemon scope
	local Rules GlobalRules Debug="" EmptyList WindowInfo LogPrio txt \
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
			\[0\]=\"desktoparrange\"\ \[* | \
			\[0\]=\"execute\"\ \[*)
				DesktopArrange "${txt}"
				;;
			MenuBarHeight=*)
				MenuBarHeight="$(cut -f 2 -s -d '=' <<< "${txt}")"
				;;
			*)
				LogPrio="err" \
				_log "Main: pipe received invalid message \"${txt}\""
				;;
			esac
		elif ! xprop -root "_NET_SUPPORTING_WM_CHECK"; then
			exit ${OK}
		fi
	done
}

set -o errexit -o nounset -o pipefail +o noglob -o noclobber

declare -ar ARGV=("${@}")
readonly ARGC=${#}

# constants
readonly NAME="$(basename "${0}")" \
	APPNAME="desktoparrange"

readonly LOGDIR="/tmp/${APPNAME}/${USER}/"

XROOT="$(GetXroot)" || \
	exit ${ERR}

readonly XROOT \
	LOGFILE="${LOGDIR}${XROOT}" \
	PIDFILE="${LOGDIR}${XROOT}.pid" \
	PIPE="${LOGDIR}${XROOT}.pipe" \
	VARSFILE="${LOGDIR}${XROOT}.vars"

cmd="${1:-}"
case "${cmd,,}" in
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
		echo "err: ${APPNAME} is not running for this session" >&2
		exit ${ERR}
	fi
	;;
desktoparrange | \
execute)
	if pid="$(AlreadyRunning)"; then
		echo "info: Interactive command: ${@}" >&2
		rule=""
		msg=""
		cmd="$(declare -p ARGV | \
			sed -re '\|^declare -ar ARGV=\((.*)\)$|s||\1|')"
		CheckTempRule "${cmd}"
		if [ -n "${rule}" ] && \
		ListRules "Temprule" "${rule}" | \
		sed -e "\|^Temprule${rule}_|s||Temprule_|" && \
		[ -z "${msg}" ]; then
			printf '%s\n' "${cmd}" >> "${PIPE}"
			echo "info: interactive command has been submitted" >&2
		else
			[ -z "${msg}" ] || \
				printf '%s\n' "${msg}" >&2
			echo "err: ${APPNAME} invalid command \"${cmd}\"" >&2
			exit ${ERR}
		fi
	else
		echo "err: ${APPNAME} is not running for this session" >&2
		exit ${ERR}
	fi
	;;
windowinfo)
	shift
	if [ -n "${1:-}" ]; then
		case "${1,,}" in
		all)
			winIds="$(wmctrl -l | \
				awk 'BEGIN{ORS="\t"}
				$2 != -1 {print $1; rc=-1}
				END{exit rc+1}')" || {
					echo "err: no open windows" >&2
					exit ${ERR}
				}
			;;
		select)
			select winId in $(wmctrl -l | \
			awk '$2 != -1 {print $0}' | \
			tr -s '[:blank:]' '_'); do
				[ -n "${winId}" ] || \
					exit ${OK}
				winIds="$(cut -f 1 -s -d '_' <<< "${winId}")"
				break
			done
			;;
		*)
			winIds="${@}"
			;;
		esac
		for winId in ${winIds}; do
			if windowId="$(printf '0x%0x' "${winId}" 2> /dev/null)" && \
			WindowExists "${windowId}"; then
				PrintWindowInfo "${windowId}"
				echo
			else
				echo "err: window \"${winId}\" doesn't exist" >&2
			fi
		done
	else
		echo "err: must specify a window ID" >&2
		exit ${ERR}
	fi
	;;
*)
	echo "err: wrong action." >&2
	echo "info: valid actions are:" >&2
	echo "start|stop|restart|reload|status|windowinfo|desktoparrange|execute" >&2
	exit ${ERR}
	;;
esac
:
