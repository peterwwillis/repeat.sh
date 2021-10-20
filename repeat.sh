#!/usr/bin/env bash
# repeat.sh - bash script to run arbitrary commands in a loop
# Copyright (C) 2021  Peter Willis

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

sleep_lock_wait="1"
sleep_after_unlock="1"
background=0
out_file='/dev/stdout'
read_delim=$'\n'
read_file=
logdir=


_exittrap () {
    trap - SIGTERM && kill -- -$$
}
_info () { echo "$(date) $0 $BASHPID: $*" ; }
_process_lock () {
    local chksum="$1"; shift
    while [ -e "$logdir/$chksum.lock" ] ; do
        read -a lock_data < "$logdir/$chksum.lock"
        ppid="${lock_data[0]}"
        cmdname="${lock_data[1]}"
        if ! kill -0 "$ppid" 2>/dev/null || [ ! "$cmdname" = "$0" ] ; then
            _info "ppid '$ppid' gone or cmdname '$cmdname' != '$0'; lock stale, removing '$logdir/$chksum.lock'"
            rm -f "$logdir/$chksum.lock"
            continue
        fi
        _info "Waiting for '$logdir/$chksum.lock'"
        sleep "$sleep_lock_wait"
    done
}
_process_cmd () {
    local lock_content result chksum

    if [ -n "$logdir" ] ; then
        lock_content="$BASHPID $0 $*"
        chksum="$(printf "%s\n" "$lock_content" | md5sum - | awk '{print $1}')"
        _process_lock "$chksum"
        echo "$lock_content" > "$logdir/$chksum.lock"
        echo "" >>"$logdir/$chksum.log"
        _info "running command: $*" >> "$logdir/$chksum.log" 2>&1
        "$@" >>"$logdir/$chksum.log" 2>&1
        result=$?
        echo "" >>"$logdir/$chksum.log"
        _info "command '$*' exited with status $result" >> "$logdir/$chksum.log" 2>&1
        rm -f "$logdir/$chksum.lock"
    else
        echo ""
        _info "running command: $*"
        "$@" 2>&1
        result=$?
        echo ""
        _info "command '$*' exited with status $result"
    fi

    sleep "$sleep_after_unlock"
}
_process_loop () {
    set +e  # Don't exit if a command fails to run
	while true ; do _process_cmd "$@" ; done
}
_process () {
    if [ $background -eq 1 ] ; then
        out_file='/dev/null'
    fi
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
        trap _exittrap SIGINT SIGTERM EXIT
        wait
    fi
}

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [COMMAND [ARGS ..]]

Continuously runs COMMAND (and any ARGS) in a loop.

If '-l' is passed, a lock file is used to track what commands are still running,
and STDOUT and STDERR are redirected to a log file. The lock file contains the
PID, process name, and command and arguments being executed. The log and lock
file names are the MD5 checksum of the contents of the lock file. The same lock
and log file names are used for the duration of a repeat.sh run (per command).

If '-f' is passed, reads a file and passes each line as a final argument to
COMMAND. If '-f' is passed but no COMMAND is passed, executes each line of the
file as a list  of COMMANDs and ARGS. If '-0' is passed, separates lines by the
null character.

Options:
  -w SEC        Seconds to sleep after a command completes and the lock is removed. ($sleep_after_unlock)
  -W SEC        Seconds to sleep in between checking for a lock to be released. ($sleep_lock_wait)
  -f FILE       Read commands from FILE. If '-', reads from standard input.
  -l DIR        Output logs and lock files to DIR.
  -o FILE       Output the loop's warnings/errors to a FILE. ($out_file)
  -0            If a FILE was passed, separate each entry by the null byte, not newlines
  -b            Fork the command(s) into the background and exit
  -h            This screen
  -v            Debug mode
EOUSAGE
    exit 1
}


while getopts "w:W:f:l:o:0bhv" args ; do
    case $args in
        w)  sleep_after_unlock="$OPTARG" ;;
        W)  sleep_lock_wait="$OPTARG" ;;
        f)  read_file="$OPTARG" ;
            if [ "$read_file" = "-" ] ; then
                read_file="/dev/stdin" ; # bash will emulate /dev/stdin
            fi ;;
        l)  logdir="$OPTARG" ;;
        o)  out_file="$OPTARG" ;;
        0)  read_delim=$'\0' ;;
        b)  background=1 ;;
        h)  _usage ;;
        v)  DEBUG=1 ; set -x ;;
        *)
            echo "$0: Error: unknown option $args" ;
            exit 1 ;;
    esac
done
shift $(($OPTIND-1))

if [ -z "$read_file" ] && [ $# -lt 1 ] ; then
    _usage
fi

if [ -n "$logdir" ] && [ ! -d "$logdir" ] ; then
    mkdir -p "$logdir"
fi

_process "$@"
