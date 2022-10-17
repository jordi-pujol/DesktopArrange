#!/bin/bash

#************************************************************************
#  DesktopArrange
#
#  Arrange Linux worskpaces
#  according to a set of configurable rules.
#
#  $Revision: 0.34 $
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

[ -n "${LOGFILE}" -a -f "${LOGFILE}" ] || \
	exit 1

set -o errexit -o nounset -o pipefail +o noglob -o noclobber

set +o xtrace
if [ "${Debug}" = "xtrace" ]; then
	export PS4='+\t ${BASH_SOURCE}:${LINENO}:${FUNCNAME:+"${FUNCNAME}:"} '
	exec >> "${LOGFILE}.xtrace" 2>&1
	set -o xtrace
else
	exec >> "${LOGFILE}" 2>&1
fi

ppid="$(ps -o ppid= ${$}))"

kill -0 ${ppid} 2> /dev/null || \
	exit 0

[ -z "${Debug}" ] || \
	echo "$(date +'%F %X') notice:" \
		"window ${windowId}:" \
		"got focus" >> "${LOGFILE}"

[ "${Debug}" != "xtrace" ] || \
	echo "$(date +'%F %X') debug:" \
		"window ${windowId}:" \
		"killing process id ${ppid} of user ${USER}" >> "${LOGFILE}"

kill ${ppid} 2> /dev/null

sleep 1
:
