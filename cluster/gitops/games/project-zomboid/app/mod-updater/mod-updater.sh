#!/bin/bash
# Restarts the server when a workshop mod has an update, but only once nobody is playing.
# The server re-downloads outdated mods on startup, so a restart is all an update needs.
#
# Talks to the server through its console: the pod shares a process namespace, so the
# server's stdin is reachable at /proc/<pid>/fd/0, and replies are read from its log.
set -u

CHECK_INTERVAL="${CHECK_INTERVAL:-900}"
REPLY_TIMEOUT="${REPLY_TIMEOUT:-60}"
RCON_PORT="${RCON_PORT:-27015}"
console_log="${DATA_DIR}/server-console.txt"

log() { printf '%s mod-updater: %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }

# Sends a console command and prints the first new log line matching the given pattern.
run_command() {
    local pid=$1 command=$2 pattern=$3 mark waited
    mark=$(wc -l < "${console_log}") || return 1
    printf '%s\n' "${command}" 2> /dev/null > "/proc/${pid}/fd/0" || return 1
    for (( waited = 0; waited < REPLY_TIMEOUT; waited++ )); do
        sleep 1
        tail -n "+$((mark + 1))" "${console_log}" | grep -m1 -E "${pattern}" && return 0
    done
    return 1
}

check() {
    local pid reply players
    # Truncated to 15 characters because that is all pgrep compares against.
    pid=$(pgrep -o ProjectZomboid6) || { log "server is not running"; return; }

    # RCON opens once the world has loaded, the same signal the probes use. Before that
    # the server is still downloading mods and loading the map.
    if ! (exec 3<> "/dev/tcp/127.0.0.1/${RCON_PORT}") 2> /dev/null; then
        log "server is still starting"
        return
    fi

    reply=$(run_command "${pid}" checkModsNeedUpdate \
        'CheckModsNeedUpdate: (Mods need update|Mods updated|Check not completed)') ||
        { log "no answer to checkModsNeedUpdate"; return; }
    case "${reply}" in
        *"Mods need update"*) ;;
        *"Mods updated"*) return ;;
        *) log "mod update check did not complete, will retry"; return ;;
    esac

    reply=$(run_command "${pid}" players 'Players connected \([0-9]+\)') ||
        { log "no answer to players"; return; }
    players=$(sed -E 's/.*Players connected \(([0-9]+)\).*/\1/' <<< "${reply}")

    if (( players > 0 )); then
        log "mod update pending, waiting for ${players} player(s) to leave"
        # cspell:words servermsg
        printf '%s\n' 'servermsg "A mod update is available. The server will restart to install it once everyone has left."' \
            2> /dev/null > "/proc/${pid}/fd/0"
        return
    fi

    # SIGTERM to the entrypoint runs its shutdown handler: save, quit, and a kill only if
    # that overruns SHUTDOWN_TIMEOUT. The kubelet then restarts the container.
    log "mod update pending and the server is empty, restarting it"
    kill -TERM "$(awk '/^PPid:/ { print $2 }' "/proc/${pid}/status")"
}

while true; do
    sleep "${CHECK_INTERVAL}"
    check
done
