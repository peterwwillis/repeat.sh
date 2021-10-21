#!/usr/bin/env bash
# repeat.sh - bash script to run arbitrary commands in a loop
# Copyright (C) 2021  Peter Willis

set -eu
[ "${DEBUG:-0}" = "1" ] && set -x

sleep_lock_wait="1"
sleep_after_unlock="1"
background=0
quiet=0
read_delim=$'\n'
read_file=
log_dir=
log_file=/dev/stdout
lock_file=


_exittrap () {
    trap - SIGTERM && kill -- -$$
}
_log () {
    local output="$1" result="${2:-0}" cmd="${3:-}" logf="$log_file"
    local log="$(date) $0 $BASHPID: $output"
    if [ "$quiet" = "1" ] && [ "$result" = "0" ] ; then
        logf="/dev/null"
    fi
    [ -z "$output" ] && log="" # print an empty line if output is empty
    echo "$log" >> "$logf"
    if [ -n "$cmd" ] ; then
        # This is where all commands are actually run!
        $cmd >> "$logf" 2>&1
    fi
}
_process_lock () {
    local chksum="$1"; shift
    while [ -e "$lock_file" ] ; do
        read -a lock_data < "$lock_file"
        ppid="${lock_data[0]}"
        cmdname="${lock_data[1]}"
        if ! kill -0 "$ppid" 2>/dev/null || [ ! "$cmdname" = "$0" ] ; then
            _log "ppid '$ppid' gone or cmdname '$cmdname' != '$0'; lock stale, removing '$lock_file'"
            rm -f "$lock_file"
            continue
        fi
        _log "Waiting for '$lock_file'"
        sleep "$sleep_lock_wait"
    done
}
_process_cmd () {
    local result chksum

    if [ -n "$log_dir" ] ; then
        chksum="$(printf "%s\n" "$0 $*" | md5sum - | awk '{print $1}')"
        lock_file="$log_dir/$chksum.lock"
        log_file="$log_dir/$chksum.log"
        _process_lock "$chksum"
        echo "$BASHPID $0 $*" > "$lock_file"
    fi

    _log ""
    _log "running command: $*" 0 "$*"
    result=$?
    _log ""
    _log "command '$*' exited with status $result" $result

    if [ -n "$lock_file" ] ; then
        rm -f "$lock_file"
    fi

    sleep "$sleep_after_unlock"
}
_process_loop () {
    set +e  # Don't exit if a command fails to run
	while true ; do _process_cmd "$@" ; done
}
_process () {
    declare -a cmds=("$@")
    if [ $background -eq 1 ] ; then
        log_file=/dev/null
    fi
    if [ -n "$read_file" ] ; then
        while IFS= read -r -d "$read_delim" arg ; do
            declare -a args=()

            if [ ${#cmds[@]} -gt 0 ] ; then
                for cmd in "${cmds[@]}" ; do
                    args=("$cmd")
                    args+=($arg)
                    _process_loop "${args[@]}" >"$log_file" 2>&1 &
                done

            else
                args+=($arg)
                _process_loop "${args[@]}" >"$log_file" 2>&1 &

            fi
        done < "$read_file"

    else
        _process_loop "$@" >"$log_file" 2>&1 &

    fi
    if [ $background -eq 0 ] ; then
        trap _exittrap SIGINT SIGTERM EXIT
        wait
    fi
}

_usage () {
    cat <<EOUSAGE
Usage: $0 [OPTIONS] [COMMAND ..]

Continuously runs one or more COMMANDs in a loop. Each COMMAND will be run by
the shell, including any arguments.

If '-l' is passed, a lock file is used to track what commands are still running,
and STDOUT and STDERR are redirected to a log file. The lock file contains the
repeat.sh PID, process name, and COMMAND. The log & lock file names are the MD5
checksum of the lock file, minus the PID. The same log & lock file names are 
used for the duration of a repeat.sh run (per command).

If '-f' is passed, reads a FILE and appends the contents to the end of each
COMMAND. If '-f' is passed but no COMMAND is passed, executes each line of the
file as a list of COMMANDs. If '-0' is passed, lines are separated by nulls.

Options:
  -w SEC        Seconds to sleep after a command completes and the lock is removed. ($sleep_after_unlock)
  -W SEC        Seconds to sleep in between checking for a lock to be released. ($sleep_lock_wait)
  -f FILE       Read commands from FILE. If '-', reads from standard input.
  -l DIR        Output logs and lock files to DIR.
  -o FILE       Output the loop's warnings/errors to a FILE. ($log_file)
  -0            If a FILE was passed, separate each entry by the null byte, not newlines.
  -b            Fork the command(s) into the background and exit.
  -q            Do not log command output or output any output unless a command fails.
  -h            This screen
  -v            Debug mode
EOUSAGE
    exit 1
}


while getopts "w:W:f:l:o:0bqhv" args ; do
    case $args in
        w)  sleep_after_unlock="$OPTARG" ;;
        W)  sleep_lock_wait="$OPTARG" ;;
        f)  read_file="$OPTARG" ;
            if [ "$read_file" = "-" ] ; then
                read_file="/dev/stdin" ; # bash will emulate /dev/stdin
            fi ;;
        l)  log_dir="$OPTARG" ;;
        o)  log_file="$OPTARG" ;;
        0)  read_delim=$'\0' ;;
        b)  background=1 ;;
        q)  quiet=1 ;;
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

if [ -n "$log_dir" ] && [ ! -d "$log_dir" ] ; then
    mkdir -p "$log_dir"
fi

_process "$@"
