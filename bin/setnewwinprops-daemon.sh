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

_unquote() {
	printf '%s\n' "${@}" | \
		sed -re "s/^([\"](.*)[\"]|['](.*)['])$/\2\3/"
}

_datetime() {
	date +'%F %X'
}

_ps_children() {
	local ppid=${1:-${$}} \
		excl="${2:-"0"}" \
		pid
	for pid in $(pgrep -P ${ppid} | \
	grep -svwEe "${excl}"); do
		_ps_children ${pid} "${excl}"
		pidsChildren="${pidsChildren}${pid}${TAB}"
	done
}

_check_int_val() {
	local n="${1}" \
		d="${2}" \
		v="" w rc=${OK}
	eval w=\"\${${n}:-}\"
	let "v=${w}" 2> /dev/null || \
		rc=${?}
	if [ ${rc} -gt 1 ] || [ -z "${v}" ]; then
		_log "Config error:" \
			"Invalid integer value \"${w}\" for \"${n}\"," \
			"assuming default \"${d}\""
		v="${d}"
	fi
	let "${n}=${v},1"
}

# priority: info notice warn err debug
_log() {
	local msg="${@}" \
		p="daemon.${LogPrio:-"notice"}"
	LogPrio=""
	printf '%s\n' "$(_datetime) ${p}: ${@}" >> "${LOGFILE}"
}

_exit() {
	local pidsChildren
	trap - EXIT INT HUP
	set +o xtrace
	LogPrio="warn" _log "Exit"
	pidsChildren=""; _ps_children
	[ -z "${pidsChildren}" ] || \
		kill -s TERM ${pidsChildren} 2> /dev/null || :
	wait || :
}

WindowName() {
	echo "$1:$2:$3"
}

AddWindow() {
	local prop valu rc=0
	while IFS="=" read -r prop valu; do
		valu="$(_unquote "${valu}")"
		[ -n "${valu}" ] || \
			continue
		case "${prop}" in
			window_get_title)
				let rc++,1
				break
			;;
		esac
	done < <(set | grep -se "^window_get_" | sort)
	if [ ${rc} -eq 0 ]; then
		_log "Error in config. Can't add a new window"
	else
		let Windows++,1
		while IFS="=" read -r prop valu; do
			valu="$(_unquote "${valu}")"
			[ -n "${valu}" ] || \
				continue
			case "${prop}" in
				window_get_title)
					eval window${Windows}_get_title=\'${valu}\'
				;;
				window_get_delay)
					eval window${Windows}_get_delay=\'${valu}\'
				;;
				window_set_position)
					eval window${Windows}_set_position=\'${valu}\'
				;;
				window_set_size)
					eval window${Windows}_set_size=\'${valu}\'
				;;
				window_set_minimized)
					eval window${Windows}_set_minimized=\'${valu}\'
				;;
				window_set_desktop)
					eval window${Windows}_set_desktop=\'${valu}\'
				;;
				window_set_active_desktop)
					eval window${Windows}_set_active_desktop=\'${valu}\'
				;;
				*)
					_log "Property \"${prop}\" is not implemented yet"
				;;
			esac
		done < <(set | grep -se "^window_[gs]et_" | sort)
		
		# 	_check_int_val "window_get_workspace" ""
		# 	_check_ind_val "window_set_active" ""
		# 	_check_yn_val "window_set_above" ""
		# 	_check_yn_val "window_set_bottom" ""
		# 	_check_ind_val "window_set_maximized" ""
		# 	_check_ind_val "window_set_maximized_horizontally" ""
		# 	_check_ind_val "window_set_maximized_vertically" ""
		# 	_check_ind_val "window_set_fullscreen" ""
		# 	_check_ind_val "window_set_focus" ""
		# 	_check_ind_val "window_set_minimized" ""
		# 	_check_yn_val "window_set_pin" ""
		# 	_check_int_pair_val "window_set_position" ""
		# 	_check_int_pair_val "window_set_size" ""
		# 	_check_int_val "window_set_active_desktop" ""
		# 	_check_int_val "window_set_desktop" ""
		# 	_check_ind_val "window_set_decoration" ""
		# 	_check_ind_val "window_set_killed" ""
		# 	_check_int_pair_val "window_set_pointer" ""
		# 
		# 	if [ -n "${Debug}" ]; then
		# 		local msg="Adding new window $( \
		# 			WindowName "${Windows}" \
		# 			"${window_bssid:-"${BEL}"}" \
		# 			"${window_ssid:-"${BEL}"}")"
		# 		_log "${msg}"
		# 	fi
	fi
	unset $(set | awk -F '=' \
		'$1 ~ "^window_" {print $1}') 2> /dev/null || :
}

LoadConfig() {
	local window_get_title \
		window_get_type \
		window_get_application \
		window_get_class \
		window_get_id \
		window_get_xid \
		window_get_pid \
		window_get_role \
		window_get_workspace \
		window_is_focussed \
		window_is_maximized \
		window_is_fullscreen \
		window_set_active \
		window_set_above \
		window_set_bottom \
		window_set_maximized \
		window_set_maximized_horizontally \
		window_set_maximized_vertically \
		window_set_fullscreen \
		window_set_focus \
		window_set_minimized \
		window_set_pin \
		window_set_position \
		window_set_size \
		window_set_active_desktop \
		window_set_desktop \
		window_set_decoration \
		window_set_killed \
		window_set_pointer \
		bash_xtracefd \
		window msg="Loading configuration"

	# config variables, default values
	Debug=""
	unset $(set | awk -F '=' \
		'$1 ~ "^window[[:digit:]]*_" {print $1}') 2> /dev/null || :

	_log "${msg}"

	Windows=${NONE}
	[ -s "${HOME}/.config/${APPNAME}/config.txt" ] && \
		. "${HOME}/.config/${APPNAME}/config.txt" || {
			LogPrio="err" _log "Invalid config file."
			exit ${ERR}
		}

	Debug="${Debug:-}"
	! printf '%s\n' "${@}" | grep -qsxiF 'debug' || \
		Debug="y"
	! printf '%s\n' "${@}" | grep -qsxiF 'xtrace' || \
		Debug="xtrace"
	if [ "${Debug}" = "xtrace" ]; then
		export PS4='+\t ${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
		exec {bash_xtracefd}>> "${LOGFILE}.xtrace"
		BASH_XTRACEFD=${bash_xtracefd}
		set -o xtrace
	else
		set +o xtrace
		exec >> "${LOGFILE}" 2>&1
	fi

	LogPrio="info" _log "${msg}"

	if [ -n "${Debug}" -o ${#} -gt ${NONE} ]; then
		msg="daemon's command line"
		[ ${#} -gt ${NONE} ] && \
			msg="${msg} options:$(printf ' "%s"' "${@}")" || \
			msg="${msg} is empty"
		_log "${msg}"
	fi

	if [ ${Windows} -eq ${NONE} ]; then
		LogPrio="warn" _log "There are not any configured windows"
	else
		local window=${NONE}
		while [ $((window++)) -lt ${Windows} ]; do
			echo
			set | grep -se "^window${window}_.*=" | sort
		done
		echo
	fi

	msg="Configuration reloaded"
	_log "${msg}"
}

WindowSet() {
	if [ -n "${delay}" ]; then
		sleep ${delay} &
		wait ${!}
	fi

	local x y
	while IFS="=" read -r prop valu; do
		#$ xprop -id 0x1e00009 | grep  _NET_WM_ALLOWED_ACTIONS
		# _NET_WM_ALLOWED_ACTIONS(ATOM) = _NET_WM_ACTION_CLOSE, _NET_WM_ACTION_ABOVE, 
		# _NET_WM_ACTION_BELOW, _NET_WM_ACTION_MINIMIZE, _NET_WM_ACTION_CHANGE_DESKTOP, 
		# _NET_WM_ACTION_STICK
		valu="$(_unquote "${valu}")"
		case "${prop}" in
			window${window}_set_position)
				valu="$(tr -s ' ,' ' ' <<< "${valu}")"
				xdotool windowmove "${windowid}" ${valu}
			;;
			window${window}_set_size)
				valu="$(tr -s ' ,' ' ' <<< "${valu}")"
				xdotool windowsize "${windowid}" ${valu}
			;;
			window${window}_set_minimized)
				xdotool windowminimize "${windowid}"
			;;
			window${window}_set_desktop)
				xdotool set_desktop_for_window "${windowid}" ${valu}
			;;
			window_set_active_desktop)
				xdotool set_desktop ${valu}
			;;
		esac
	done < <(set | grep -se "^window${window}_set_" | sort)
}

WindowNew() {
	local windowid="${1}" \
		window_get_title \
		window_get_type \
		window_get_application \
		window_get_class \
		window_get_id \
		window_get_xid \
		window_get_pid \
		window_get_role \
		window delay="" \
		WIDTH HEIGHT desktopCurrent desktops

	eval $(xdotool getdisplaygeometry --shell)
	desktopCurrent="$(xdotool get_desktop)"
	desktops="$(xdotool get_num_desktops)"

	window_get_title="$(xprop -id "${windowid}" _NET_WM_NAME | \
		sed -re '\|.*[=] "(.*)"$| s//\1/')"
	window_get_type="$(xprop -id "${windowid}" _NET_WM_WINDOW_TYPE | \
		awk '{print $NF}')"
	window_get_pid="$(xprop -id "${windowid}" _NET_WM_PID | \
		awk '{print $NF}')"
	window_get_application="$(ps -ho cmd "${window_get_pid}")"
	window_get_class="$(xprop -id "${windowid}" _NET_WM_CLASS | \
		cut -f 2- -s -d '=')"
	#window_get_id
	#window_get_xid
	# window_get_role="$(xprop -id "${windowid}" _NET_WM_CLASS | \
	#	cut -f 2- -s -d '=')"
#	xdotool
#	getwindowpid "${windowid}"
#	getwindowname "${windowid}"
#	getwindowgeometry [--shell] "${windowid}"
#		Output the geometry (location and position) of a window.
#		The values include: x, y, width, height, and screen number.

	window=${NONE}
	while [ $((window++)) -lt ${Windows} ]; do
		local rc="y" prop valu
		while [ -n "${rc}" ] && \
		IFS="=" read -r prop valu; do
			valu="$(_unquote "${valu}")"
			case "${prop}" in
				window${window}_get_title)
					[ "${valu}" = "${window_get_title}" ] || \
						rc=""
				;;
				window${window}_get_delay)
					delay="${valu}"
				;;
				*)
					rc=""
				;;
			esac
		done < <(set | grep -se "^window${window}_get_" | sort)
		if [ -n "${rc}" ]; then
			WindowSet &
			break
		fi
	done
}

WindowsUpdate() {
	local windowid
	for windowid in "${@}"; do
		grep -qswF "${windowid}" <<< "${WindowIds}" || \
			WindowNew "${windowid}" || :
	done
	WindowIds="${@}"
}

Main() {
	# constants
	readonly NAME \
		TAB=$'\t' OK=0 ERR=1 NONE=0 \
		XROOT="$(xprop -root _NET_SUPPORTING_WM_CHECK | \
			awk '{print $NF; exit}')"
	readonly LOGFILE="/tmp/${APPNAME}/${USER}/${XROOT}" \
		PIDFILE="/tmp/${APPNAME}/${USER}/${XROOT}.pid"
		FIFO="/tmp/${APPNAME}/${USER}/${XROOT}.fifo"
	# internal variables, daemon scope
	local Windows Debug LogPrio txt \
		WindowIds pidsChildren pid pidfifo \
		LogOutput="/dev/null"

	trap '_exit' EXIT
	trap 'exit' INT
	trap 'echo reload >> "${FIFO}"' HUP

	mkdir -p -m 0777 "/tmp/${APPNAME}"
	mkdir -p -m 0755 "/tmp/${APPNAME}/${USER}"
	echo "${$}" > "${PIDFILE}"
	[ -e "${FIFO}" ] || \
		mkfifo "${FIFO}"
	exec >> "${LOGFILE}" 2>&1

	LogPrio="warn" _log "Start"
	WindowIds=""
	LoadConfig "${@}"

	xprop -root -spy "_NET_CLIENT_LIST_STACKING" >> "${FIFO}" &
	pidfifo="${!}"
	while :; do
		if read -r txt < "${FIFO}"; then
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
		# clear finished children processes
		pidsChildren=""; _ps_children "" ${pidfifo}
		for pid in ${pidsChildren}; do
			kill -s 0 ${pid} 2> /dev/null || \
				wait ${pid} || :
		done
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
