#!/bin/sh

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

. /usr/lib/setnewwinprops/setnewwinprops.sh

_exit() {
	local pidsChildren
	trap - EXIT INT
	set +o xtrace
	LogPrio="warn" _log "Exit"
	pidsChildren=""; _ps_children
	[ -z "${pidsChildren}" ] || \
		kill -s TERM ${pidsChildren} 2> /dev/null || :
	wait || :
}

_dialog_init() {
	local size
	[ -n "${JA_DIALOG_TAILBOXMSG:+"${JA_DIALOG_TAILBOXMSG}"}" ] || \
		JA_DIALOG_TAILBOXMSG="${JA_USRACT_DIR:-"${JA_USR_DIR}"}user.msgq"
	# variables that are already set in Bash environment, LINES and COLUMNS
# 	export JA_DIALOG_SCREEN_HEIGHT=`tput lines`
# 	export JA_DIALOG_SCREEN_WIDTH=`tput cols`
# 	echo "lines,columns: ${LINES:-} ${COLUMNS:-}" >&2
	_fd_restore
	size="$(dialog --print-maxsize --stdout)"
	_fd_save
	export JA_DIALOG_SCREEN_WIDTH="$(awk '{print $3+0}' <<< "${size}" )"
	test ${JA_DIALOG_SCREEN_WIDTH} -ge 80 || \
		JA_DIALOG_SCREEN_WIDTH=80
	export JA_DIALOG_SCREEN_HEIGHT="$(awk '{print $2+0}' <<< "${size}" )"
	test ${JA_DIALOG_SCREEN_HEIGHT} -ge 25 || \
		JA_DIALOG_SCREEN_HEIGHT=25
	export JA_DIALOG_WIDTH=$((JA_DIALOG_SCREEN_WIDTH))
	export JA_DIALOG_HEIGHT=$((JA_DIALOG_SCREEN_HEIGHT-14))
}

_dialog_end() {
	_fd_restore
	#clear
}

_dialog_header_form() {
	local r s column w field_width label_width
	w=$((JA_DIALOG_WIDTH-3))
	r=" "
	column=1
	for s in ${JA_DIALOG_FIELDS}; do
		field_width="$(cut -f 2 -s -d ':' <<< "${s}")"
		label_width="$(cut -f 4 -s -d ':' <<< "${s}")"
		[ -n "${label_width}" ] || \
			label_width=0
		[ ${label_width} -eq 0 ] && \
			label_width=${field_width//[.]/} || \
			label_width=$((label_width+${field_width//[.]/}))
		if grep -qs -e '\.$' <<< "${field_width}"; then
			r="${r}$(printf "%${label_width}.${label_width}s" \
				"$(cut -f 1 -s -d ':' <<< "${s}")" | tr ' ' '_')"
		else
			r="${r}$(printf "%.${label_width}s" \
			"$(cut -f 1 -s -d ':' <<< "${s}")" | tr ' ' '_')"
		fi
		column=$((column+label_width+1))
		[ ${column} -le ${w} ] || column=${w}
		while [ $(sed -e 's|\\Z.||g' <<< "${r}" | wc --chars) -lt ${column} ]; do
			r="${r}_"
		done
		r="${r} "
	done
	printf '%s\n' " ${JA_DIALOG_FKEYS}# ${JA_DIALOG_COMMANDS}#${r}"
}

_dialog_header() {
# --trace "${JA_DIALOG_TRACE}"
	printf '%s\n' "dialog --output-fd 7 --stdout --no-shadow --separator '#' \
--colors \
--begin $((JA_DIALOG_HEIGHT)) 0 \
--title Messages --tailboxbg ${JA_DIALOG_TAILBOXMSG} \
$((JA_DIALOG_SCREEN_HEIGHT-JA_DIALOG_HEIGHT)) ${JA_DIALOG_SCREEN_WIDTH} \
--and-widget \
--begin 0 0 \
--title ${1//[[:blank:]]/_} \
--help-button --help-status \
--extra-button --extra-label Rfrsh${autorefresh:+":AUTO"} \
--last-key \
--colors \
--default-item '${JA_DIALOG_LABEL}' \
--form '$(_dialog_header_form)' ${JA_DIALOG_HEIGHT} ${JA_DIALOG_WIDTH} $((JA_DIALOG_HEIGHT-8)) "
}

_dialog_line() {
	local field field_input field_width label label_width column
	local i dialog_fields

	# suppress blank columns in the right side
	for i in $(eval echo "{${#}..1}"); do
		[ -z "$(eval echo "\${${i}}")" ] || \
			break
	done
	dialog_fields="$(cut -f -${i} -d ' ' <<< "${JA_DIALOG_FIELDS}")"

	column=1
	for s in ${dialog_fields}; do
		field="$(cut -f 1 -d '#' <<< "${1}"| tr "'" '"')"
		[[ ! "${field}" =~ ^- ]] || \
			field=" ${field}"
		field_width="$(awk 'BEGIN{FS="#"}
			$3 ~ "^[[:digit:]]+$" {print $3}' <<< "${1}")"
		field_input="$(awk 'BEGIN{FS="#"}
			$2 ~ "^[[:digit:]]+$" {print $2}' <<< "${1}")"
		field_width="${field_width:-"$(cut -f 2 -s -d ':' <<< "${s}")"}"
		field_input="${field_input:-"$(cut -f 3 -s -d ':' <<< "${s}")"}"
		label_width="$(cut -f 4 -s -d ':' <<< "${s}")"
		[ -n "${field_input}" ] || \
			field_input=0
		[ -n "${label_width}" ] || \
			label_width=0
		label=""
		if [ ${label_width} -gt 0 ]; then
			local field_width1 field_input1
			label="$(printf "%.${label_width}s" "${field}")"
			shift
			field="$(cut -f 1 -d '#' <<< "${1}"| tr "'" '"')"
			[[ ! "${field}" =~ ^- ]] || \
				field=" ${field}"
			field_width1="$(awk 'BEGIN{FS="#"}
				$3 ~ "^[[:digit:]]+$" {print $3}' <<< "${1}")"
			[ -z "${field_width1}" ] || \
				field_width=${field_width1}
			field_input1="$(awk 'BEGIN{FS="#"}
				$2 ~ "^[[:digit:]]+$" {print $2}' <<< "${1}")"
			[ -z "${field_input1}" ] || \
				field_input=${field_input1}
		fi
		if grep -qs -e '\.$' <<< "${field_width}"; then
			field_width="${field_width//[.]/}"
			field="$(printf "%${field_width}.${field_width}s" \
				"${field}")"
		else
			field="$(printf "%.${field_width}s" "${field}")"
		fi
		printf '%s ' "'${label}'" "${line}" "${column}" "'${field}'" \
			"${line}" "$((column+label_width))" \
			"$(test ${field_input} -eq 0 && echo 0 || echo ${field_width})" \
			"${field_input}"
		printf '\n'
		column=$((column+label_width+field_width+1))
		shift
	done
}

_dialog_options() {
	local value="${1}" prompt="${2}"
	local w o

	w=$((JA_DIALOG_WIDTH-15))
	if [ ${w} -gt 80 ]; then
		o=${w}
	else
		o=80
	fi
	[[ ! ${value} =~ ^- ]] || \
		value=" ${value}"
	printf '%s ' "'${prompt}:'" "${line}" "1" "'${value}'" \
		"${line}" "12" "${w}" "${o}"
	printf '\n'
}

_dialog_fkeys() {
	awk -v fkeys="${1}" 'BEGIN{split(fkeys, fk)
		for (v in fk) keys[fk[v]]}
		$1 in keys {printf $2 " "}' "${JA_CONF_FKEYS}"
}

_dialog_exec() {
	local dialogrc="${1:-}"
	local M rc
	rc=0
	M="$(eval "DIALOGRC=${dialogrc} $(tr -s '#' '\n' <<< "${DIALOG//[$'\n']/ }")")" || \
		rc="${?}"
	sed -re '\|.*\[2J| s|||' <<< "${M}"
#		\|^[[:blank:]]+| s|||
#		\|[[:blank:]]+$| s|||' <<< "${M}"
	return "${rc}"
}

_interactive_dialog() {
	let ++line,1
	DIALOG="${DIALOG}$(_dialog_options "${cmd_options}" "Parms-Cmd")"
	rc=0
	M="$(_dialog_exec "${JA_CONF_DLG}")" || \
		rc="${?}"

	case "${rc}" in
	0) # Enter
		lastkey="$(_print_line ${line} <<< "${M}")"
		;;
	1|255) # 1=Cancel 255=Esc or ERR, does not contain keycode
		rc=0
		return 1
		;;
	2) # Help
		JA_DIALOG_LABEL="$(awk 'NR == 1 {if ($1 == "HELP") {
			$1=""
			gsub(/^[[:blank:]]+|[[:blank:]]+$/, "")
			print }
			exit }' <<< "${M}")"
		M="$(_print_line '2,$' <<< "${M}")"
		lastkey="$(_print_line ${line} <<< "${M}")"
		;;
	3) # Extra button
		lastkey=269 # F5
		;;
	*)
		lastkey=""
		JA_DIALOG_LABEL=""
		;;
	esac

	_lastkey_detect "${lastkey}"

	if [ -n "${JA_FKEY_END}" -o \
	-n "${JA_FKEY_CANCEL}" ]; then
		return 1
	fi

	cmd_options="$(_print_line "$((line-1))" <<< "${M}")"
	if [ $((line-2)) -gt 0 ]; then
		M="$(_print_line "1,$((line-2))" <<< "${M,,}")"
	else
		M=""
	fi

	if [ -n "${JA_FKEY_AUTOREFRESH}" ]; then
		autorefresh="$(test -n "${autorefresh}" || echo "y")"
		return 0
	fi
	if [ -n "${JA_FKEY_DSPMSG}" ]; then
		if _cmd_dsc "dspmsg"; then
			JA_CMD_ARGS=("--msgq" "$(basename "${JA_DIALOG_TAILBOXMSG}" ".msgq")")
			_cmd_exec || :
		fi
		return 0
	fi
	if [ -n "${JA_FKEY_HELP}" ]; then
		_help_cmds
		return 0
	fi
	if [ -n "${JA_FKEY_REFRESH}" -o \
	-n "${JA_FKEY_PARMS}" -o \
	-n "${JA_FKEY_RETRIEVE}" -o \
	-n "${JA_FKEY_CHGVIEW}" ]; then
		if [ -z "${M}" ]; then
			if [ -n "${JA_FKEY_RETRIEVE}" ]; then
				[ -n "${cmd_options}" ] || \
					cmd_index=0
				cmd_options="$(_cmd_retrieve)"
				cmd_index="$((cmd_index+1))"
				return 0
			fi
			if [ -n "${cmd_options}" ]; then
				_usr_notify "Can't refresh while there are pending options." \
					"" "y"
				JA_DIALOG_LABEL="Parms-Cmd:"
				return 0
			fi
		else
			_usr_notify "Can't modify display while there are pending options." \
				"" "y"
			JA_DIALOG_LABEL="$(awk '$0 {print NR; exit}' <<< "${M}")"
			return 0
		fi
	fi
	if [ -n "${JA_FKEY_REFRESH}" ]; then
		SetNewWinProps_refresh
		return 0
	fi
	if [ -n "${JA_FKEY_ENTER}" -o \
	-n "${JA_FKEY_ASSIST}" ]; then
		if [ -n "${M}" ]; then
			local m e sfl_line \
				err="" i=0 M0="${M}" sfl_c=$(wc -l <<< "${M}")
			while [ $((++i)) -le ${sfl_c} ]; do
				m="$(_print_line "${i}" <<< "${M}")"
				[ -n "${m}" ] || \
					continue
				e=""
				JA_CMD_ARGS=()
				JA_CMD_CMD=""
				sfl_line="$(_print_line "${i}" <<< "${subfile}")"
				if SetNewWinProps_lineOK; then
					if [ -n "${JA_CMD_CMD}" ]; then
						[ -z "${cmd_options}" ] || \
							eval JA_CMD_ARGS+=(${cmd_options})
						if [ -z "${JA_FKEY_CONFIRM}" -a \
						"${JA_CMD_TERMINAL}" -lt 1 ]; then
							_cmd_exec_background || e="No"
						else
							_cmd_exec || e="No"
						fi
					else
						e="Yes"
					fi
				else
					e="Yes"
				fi
				if [ -z "${e}" ]; then
					M0="$(sed -e ${i}'s|.*||' <<< "${M0}")"
				else
					[ "${e}" != "Yes" ] || \
						_usr_notify "Invalid option '${m}'." "" "y"
					if [ -z "${err}" ]; then
						JA_DIALOG_LABEL="${i}"
						err="Yes"
					fi
				fi
			done
			if [ -n "${err}" ]; then
				M="${M0}"
			else
				SetNewWinProps_refresh "y"
			fi
		elif [ -n "${cmd_options}" ] && \
		eval JA_CMD_ARGS=(${cmd_options}); then
			if _cmd_dsc "${JA_CMD_ARGS[@]}"; then
				unset JA_CMD_ARGS[0]
				if [ -z "${JA_FKEY_CONFIRM}" -a \
				"${JA_CMD_TERMINAL}" -lt 1 ]; then
					if _cmd_exec_background; then
						SetNewWinProps_refresh "y"
					fi
				else
					if _cmd_exec; then
						SetNewWinProps_refresh "y"
					fi
				fi
			else
				_cmd_exec_shell
				SetNewWinProps_refresh "y"
			fi
		else
			SetNewWinProps_refresh "y"
		fi
		return 0
	fi
	if [ -n "${JA_FKEY_CHGVIEW}" ]; then
		let ++JA_SEQ,1
		SetNewWinProps_chgview
		SetNewWinProps_refresh
		return 0
	fi
	if [ -n "${JA_FKEY_PARMS}" ]; then
		_jobadmin_parms_vars
		return 0
	fi

	[ ${rc} != 0 ] || \
		SetNewWinProps_refresh
}

SetNewWinProps_chgview() {
	case "${JA_SEQ}" in
	2)
		JA_DIALOG_FIELDS="Opt:3:2:3 Subsystem/Job:30 Stat:10 MaxJ:5. ActvJ:5. Pri:3. Date:19 Job_Queue:15"
		;;
	3)
		JA_DIALOG_FIELDS="Opt:3:2:3 Subsystem/Job:30 Stat:10 M/CPU:6. A/Mem:6. Pri:3. Date:19 Job_Queue/Cmds:20"
		;;
	*)
		JA_DIALOG_FIELDS="Opt:3:2:3 Subsystem/Job:30 Stat:10 MaxJ:5. ActvJ:5. Pri:3. Date:19"
		JA_SEQ=1
		;;
	esac
}

SetNewWinProps_rules() {
	local timerls job usr sts stsord sbsd jobq jobq_sts pty attrs
	local sbsd_previous jobq_previous d

	sbsd_previous=""; jobq_previous=""
	jobqs=""
	unset timerls job usr sts stsord sbsd jobq jobq_sts pty attrs
	while IFS=$'\t' read timerls job usr sts stsord sbsd jobq jobq_sts \
	pty attrs rest; do
		[ -n "${timerls}" ] || continue
		if [ "${sbsd_previous}" != "${sbsd}" ]; then
			if [ "${JA_SEQ}" = "1" ] && \
			[ -n "${sbsd_previous}" ]; then
				for jobq1 in ${jobqs}; do
					SetNewWinProps_jobq_line "${jobq1}" "${sbsd_previous}"
				done
				jobqs=""
			fi
			SetNewWinProps_sbsds "${sbsd}"
			sbsd_previous="${sbsd}"
		fi
		if [ "${jobq_previous}" != "${jobq}" ] && \
		[ "${JA_SEQ}" = "1" ]; then
			SetNewWinProps_jobqs "${jobq}" "${sbsd}"
			jobq_previous="${jobq}"
		fi

		d="$(dirname "${attrs}")"
		job_pid=""
		if [ -d "${d}" ]; then
			pidfile="${d}/job.pid"
			if [ -s "${pidfile}" ]; then
				job_pid="$(cat "${d}/job.pid")" && \
				kill -0 "${job_pid}" 2> /dev/null || \
					job_pid=""
			fi
		else
			sts="ERR"
		fi

		local hld="$(_read_option "JA_HLD" "${JA_SPOOL}${jobq}.jobq.attrs")" || :
		printf '%s ' "${job}.${usr}${job_pid:+".${job_pid}"}" \
			"${sts}" "-" "-" "${pty}" "${timerls}" \
			"${jobq}$(test "${jobq_sts}" = "-" || printf '%s' "/${jobq_sts}")" \
			"${attrs}"
		printf '\n'
		unset timerls job usr sts stsord sbsd jobq jobq_sts pty attrs
	done <<< "${list_rules}"
	[ "${JA_SEQ}" != "1" ] || \
		[ -z "${jobqs}" ] || \
			SetNewWinProps_jobqs "---" "${sbsd_previous}"
	[ -z "${sbsds}" ] || \
		SetNewWinProps_sbsds "---"
	:
}

SetNewWinProps_refresh() {
	local auto="${1:-}"
	# global subfile sfl_rec_count M cmd_options
	local list_rules
	local jobqs sbsds

	M=""; cmd_options=""; JA_DIALOG_LABEL=""
	if [ -n "${auto}" ]; then
		[ -n "${autorefresh}" ] || \
			return 0
		sleep 1
	fi

	LoadConfig
	if [ "${JA_SEQ}" = "1" ]; then
		list_rules="$(_find_rules "${JA_USRS}" "${JA_SBSDS}" \
			"${JA_JOB_STSS}" "${JA_JOBQS}" "${JA_SBSTYPS}" | \
			sort -t $'\t' -k 6,6 -k 7,7 -k 5n,5 -k 9nr,9 -k 1n,1)"
	else
		list_rules="$(_find_rules "${JA_USRS}" "${JA_SBSDS}" \
			"${JA_JOB_STSS}" "${JA_JOBQS}" "${JA_SBSTYPS}" | \
			sort -t $'\t' -k 6,6 -k 5n,5 -k 9nr,9 -k 1n,1)"
	fi
	subfile="$(SetNewWinProps_rules)"
	sfl_rec_count="$(wc -l <<< "${subfile}")"
	:
}

SetNewWinProps_lineOK() {
	case "${sfl_line}" in
	SBS/*)
		_cmd_abv_dsc "${m}" "SBS,SYS" || \
			return 1
		if grep -qswe "SBS" <<< "${JA_CMD_OBJ}"; then
			_options_reuse "${JA_CMD_CMD}" \
			"JA_SBSD=$(cut -f 2 -s -d '/' <<< "${sfl_line/[[:blank:]]*/}")"
		fi
		;;
	JOBQ/*)
		_cmd_abv_dsc "${m}" "JOBQ,SYS" || \
			return 1
		if echo "${JA_CMD_OBJ}" | grep -qswe "JOBQ"; then
			_options_reuse "${JA_CMD_CMD}" \
			"JA_JOBQ=$(cut -f 2 -s -d '/' <<< "${sfl_line/[[:blank:]]*/}")"
		fi
		;;
	*)
		_cmd_abv_dsc "${m}" "JOB,JOBQ,OUTQ,SYS" || \
			return 1
		if echo "${JA_CMD_OBJ}" | grep -qswe "JOB"; then
			local job="${sfl_line/[[:blank:]]*/}"
			_options_reuse "${JA_CMD_CMD}" \
			"JA_JOB=$(cut -f 1 -s -d '.' <<< "${job}")" \
			"JA_USR=$(cut -f 2 -s -d '.' <<< "${job}")" \
			"JA_PID=$(cut -f 3 -s -d '.' <<< "${job}")"
		elif echo "${JA_CMD_OBJ}" | grep -qswe "JOBQ"; then
			_options_reuse "${JA_CMD_CMD}" \
			"JA_JOBQ=$(awk '{print $7; exit}' <<< "${sfl_line}" | \
			cut -f 1 -d '/')"
		elif echo "${JA_CMD_OBJ}" | grep -qswe "OUTQ"; then
			_options_reuse "${JA_CMD_CMD}" \
			"JA_OUTQ=$(_read_option "JA_OUTQ" \
			"$(awk '{print $NF}' <<< "${sfl_line}")")"
		fi
		;;
	esac
}

Main() {
	local job f timerls
	local sbsd sbsd_maxjobs
	local jobq jobq_sbsd jobq_maxjobs jobq_onerror
	local jobs_active jobs_active_sbsd
	local a job f timerls line DIALOG job_pid job_pids status
	local lastkey M cmd_options subfile sfl_rec_count rc obj
	local autorefresh="${JA_AUTOREFRESH:-}"

	JA_DIALOG_COMMANDS="dis\Z1P\Znlay \Z1C\Znhgrule \Z1D\Znltrule"
	JA_DIALOG_FKEYS="$(_dialog_fkeys "F1 F2 F4 F5 F6 F9 F11 F12")"
	JA_DIALOG_LABEL=""

	SetNewWinProps_chgview
	SetNewWinProps_refresh
	rc=0
	while :; do
		_dialog_init
		DIALOG="$(_dialog_header "${JA_MODULE_NAME}")"
		line=1
		i=0
		unset f1 f2 f3 f4 f5 f6 f7 f8
		while read f1 f2 f3 f4 f5 f6 f7 f8 && \
		let ++i,1; do
			[ -n "${f1}" ] || continue
			# formatted listing of rule data
			grep -qsE '^SBS|^JOBQ' <<< "${f1}" || \
				[ "${f6}" = "-" ] || \
				f6="$(_datetime --date=@${f6})"
			m="$(_print_line "${i}" <<< "${M}")"
			case "${JA_SEQ}" in
			3)
				if ! grep -qsE '^SBS|^JOBQ' <<< "${f1}" && \
				[ "${f2}" = "ACT" ]; then
					rule_pid="$(cut -f 3 -s -d '.' <<< "${f1}" )"
					if [ -n "${rule_pid}" ] && \
					kill -0 "${rule_pid}" 2> /dev/null && \
					cmdl="$(_commands_exec "${rule_pid}")"; then
						f3="$(cut -f 1 -d ' ' <<< "${cmdl}" | \
						sed -re '/([[:digit:]])$/ s//.\1/')%"
						f4="$(cut -f 2 -d ' ' <<< "${cmdl}" | \
						sed -re '/([[:digit:]])$/ s//.\1/')%"
						f7="$(cut -f 3- -d ' ' <<< "${cmdl}" | \
						tr -s '[:blank:]' '_')"
					else
						f3="0%"
						f4="0%"
					fi
				fi
				DIALOG="${DIALOG}$(_dialog_line "${i}" "${m}" \
					"${f1}" \
					"${f2}" \
					"${f3}" \
					"${f4}" \
					"${f5}" \
					"${f6}" \
					"${f7}")"
				;;
			2)
				DIALOG="${DIALOG}$(_dialog_line "${i}" "${m}" \
					"${f1}" \
					"${f2}" \
					"${f3}" \
					"${f4}" \
					"${f5}" \
					"${f6}" \
					"${f7}")"
				;;
			*)
				DIALOG="${DIALOG}$(_dialog_line "${i}" "${m}" \
					"${f1}" \
					"${f2}" \
					"${f3}" \
					"${f4}" \
					"${f5}" \
					"${f6}")"
				;;
			esac
			let ++line,1
			unset f1 f2 f3 f4 f5 f6 f7 f8
		done <<< "${subfile}"
		# show dialog
		_interactive_dialog || \
			break
	done
	_dialog_end
	return "${rc}"
} # Main

Main
:
