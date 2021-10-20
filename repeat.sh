#!/usr/bin/env bash
# repeat.sh - bash script to run arbitrary commands in a loop
# Copyright (C) 2021  Peter Willis

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

logdir="logs"
zero="$(readlink -f "$0")"
sleep_lock_wait="1"
sleep_after_unlock="1"
background=0
read_delim=$'\n'
read_file=
out_file=/dev/stdout

_process_lock () {
    local lock_content="$BASHPID $zero $*"
	local chksum="$(printf "%s\n" "$lock_content" | md5sum - | awk '{print $1}')"

	while [ -e "$logdir/$chksum.lock" ] ; do
        read -a lock_data < "$logdir/$chksum.lock"
		ppid="${lock_data[0]}"
		cmdname="${lock_data[1]}"
		if ! kill -0 "$ppid" 2>/dev/null || [ ! "$cmdname" = "$zero" ] ; then
			echo "ppid '$ppid' gone or cmdname '$cmdname' != '$zero'; lock stale, removing '$logdir/$chksum.lock'"
			rm -f "$logdir/$chksum.lock"
			continue
		fi

		echo "$zero: $BASHPID: Waiting for '$logdir/$chksum.lock'"
		if [ "${sleep_wait_lock:-0}" -gt 0 ] ; then
            sleep "$sleep_lock_wait"
        fi
	done

	echo "$lock_content" > "$logdir/$chksum.lock"
    echo "$zero: $BASHPID: Running command: $*"
	"$@" >>"$logdir/$chksum.log" 2>&1
	rm -f "$logdir/$chksum.lock"
    if [ "${sleep_after_unlock:-0}" -gt 0 ] ; then
        sleep "$sleep_after_unlock"
    fi
}
_process_loop () {
    set +e  # Don't exit if a command fails to run
	while true ; do _process_lock "$@" ; done
}
_process () {
    if [ -n "$read_file" ] ; then
        while IFS= read -r -d "$read_delim" arg ; do
            declare -a args=()
            [ $# -gt 0 ] && args=("$@")
            args+=("$arg")
            _process_loop "${args[@]}" >"$out_file" 2>&1 &
        done < "$read_file"
    else
        _process_loop "$@" >"$out_file" 2>&1 &
    fi
    if [ $background -eq 0 ] ; then
        wait
    fi
}

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [COMMAND [ARGS ..]]

Continuously runs COMMAND (and any ARGS) in a loop.

A lock file is used to track what commands are still running, and STDOUT and
STDERR are redirected to a log file. The lock file contains the PID, process
name, and command and arguments being executed. The log and lock file names are
the MD5 checksum of the contents of the lock file.

If '-f' is passed, reads a file and passes each line as a final argument to
COMMAND. If '-f' is passed but no COMMAND is passed, executes each line of the
file as a list  of COMMANDs and ARGS. If '-0' is passed, separates lines by the
null character.

Options:
  -W SEC        Seconds to sleep in between checking for a lock to be released. ($sleep_lock_wait)
  -A SEC        Seconds to sleep after a command completes and the lock is removed. ($sleep_after_unlock)
  -f FILE       Read commands from FILE. If '-', reads from standard input.
  -l DIR        The directory to keep log and lock files. ($logdir)
  -o FILE       Output the loop's warnings/errors to a FILE. ($out_file)
  -0            If a FILE was passed, separate each entry by the null byte, not newlines
  -b            Fork the command(s) into the background and exit
  -h            This screen
  -v            Debug mode
EOUSAGE
    exit 1
}


while getopts "W:A:f:l:o:0bhv" args ; do
    case $args in
        W)  sleep_lock_wait="$OPTARG" ;;
        A)  sleep_after_unlock="$OPTARG" ;;
        f)  read_file="$OPTARG" ;
            if [ "$read_file" = "-" ] ; then
                read_file="/dev/stdin" ; # bash will emulate /dev/stdin
            fi ;;
        l)  logdir="$OPTARG" ;;
        o)  out_file="$OPTARG" ;;
        0)  read_delim=$'\0' ;;
        b)  background=1 ;;
        h)  _usage ;;
        v)  export DEBUG=1 ;;
        *)
            echo "$0: Error: unknown option $args" ;
            exit 1 ;;
    esac
done
shift $(($OPTIND-1))

if [ -z "$read_file" ] && [ $# -lt 1 ] ; then
    _usage
fi

[ -d "$logdir" ] || mkdir -p "$logdir"

_process "$@"
