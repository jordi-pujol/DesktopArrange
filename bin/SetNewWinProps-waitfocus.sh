#!/bin/bash

#************************************************************************
#  SetNewWinProps
#
#  Change window properties for opening windows
#  according to a set of configurable rules.
#
#  $Revision: 0.8 $
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

if [ "${Debug}" = "xtrace" ]; then
	export PS4='+\t ${BASH_SOURCE}:${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
	exec >> "${LOGFILE}.xtrace" 2>&1
	set -o xtrace
else
	exec >> "${LOGFILE}" 2>&1
fi

pids="$(ps -C "${cmd}" -o pid= -o user= | \
	awk -v user="${USER}" \
	'$2 == user && $1 ~ "^[[:digit:]]+$" {printf $1 " "; rc=-1}
	END{exit rc+1}')" || \
		exit 1

kill ${pids} 2> /dev/null

[ -z "${Debug}" ] || \
	echo "$(date +'%F %X') daemon.notice:" \
		"window ${windowId}:" \
		"got focus" >> "${LOGFILE}"

[ "${Debug}" != "xtrace" ] || \
	echo "$(date +'%F %X') daemon.notice:" \
		"window ${windowId}:" \
		"killing process ${pids} of user ${USER} \"${cmd}\"" >> "${LOGFILE}"
:
