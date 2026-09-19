#!/bin/bash
# The world is only written to disk when the server is told to save, so a plain SIGTERM costs
# everything since the last autosave. This wrapper holds a pipe on the server's stdin and feeds it
# "save" then "quit" on SIGTERM, then waits for the server to exit on its own.
set -euo pipefail

SERVER_DIR="${SERVER_DIR:-/opt/pz-server}"
SERVER_NAME="${SERVER_NAME:-pzserver}"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
BIND_IP="${BIND_IP:-}"
PORT="${PORT:-16261}"
DATA_DIR="${DATA_DIR:-/var/lib/zomboid}"
STEAM_VAC="${STEAM_VAC:-true}"
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-120}"

log() { printf 'entrypoint: %s\n' "$*" >&2; }

# Without a password on the first start the server stops on an interactive prompt that nothing is
# there to answer, which looks like a hang rather than a failure.
if [[ -z "${ADMIN_PASSWORD}" && ! -f "${DATA_DIR}/Server/${SERVER_NAME}.ini" ]]; then
    log "ADMIN_PASSWORD must be set the first time ${SERVER_NAME} is started"
    exit 1
fi

if [[ ! -w "${DATA_DIR}" ]]; then
    log "${DATA_DIR} is not writable by $(id -u):$(id -g), and the save, player database, server config and logs all live there"
    exit 1
fi

# Workshop mods are downloaded by the server on every start, into steamapps/workshop inside the
# image. Kept there they would be re-fetched from Steam after every restart, so the directory is
# pointed at the data volume instead. Steam still updates them in place.
workshop_dir="${DATA_DIR}/workshop"
mkdir -p "${workshop_dir}"
if [[ "$(readlink -f "${SERVER_DIR}/steamapps/workshop" || true)" != "$(readlink -f "${workshop_dir}")" ]]; then
    rm -rf "${SERVER_DIR}/steamapps/workshop"
    ln -s "${workshop_dir}" "${SERVER_DIR}/steamapps/workshop"
fi

server_args=(
    "-cachedir=${DATA_DIR}"
    -servername "${SERVER_NAME}"
    -adminusername "${ADMIN_USERNAME}"
    -port "${PORT}"
    -steamvac "${STEAM_VAC}"
)

# Only when asked for: the server binds every interface without it, and `-ip 0.0.0.0` - the obvious
# way to write "all of them" - makes it exit about a second after Steam initialises, silently.
if [[ -n "${BIND_IP}" ]]; then
    server_args+=(-ip "${BIND_IP}")
fi

if [[ -n "${ADMIN_PASSWORD}" ]]; then
    server_args+=(-adminpassword "${ADMIN_PASSWORD}")
fi

# Anything the image does not model, e.g. -nosteam or -modfolders.
if [[ -n "${EXTRA_SERVER_ARGS:-}" ]]; then
    # Word splitting is what is wanted here.
    # shellcheck disable=SC2206
    server_args+=(${EXTRA_SERVER_ARGS})
fi

# Anything before the launcher's `--` is appended to the VM args it reads out of
# ProjectZomboid64.json, and a later -Xmx wins, so this is how the heap is set without writing to
# the game directory. _JAVA_OPTIONS does not work: the launcher clears it before it creates the VM.
vm_args=()
if [[ -n "${MAX_HEAP:-}" ]]; then
    vm_args+=("-Xmx${MAX_HEAP}")
fi

if [[ -n "${EXTRA_JAVA_OPTS:-}" ]]; then
    # shellcheck disable=SC2206
    vm_args+=(${EXTRA_JAVA_OPTS})
fi

# The environment start-server.sh sets, with one correction: it puts jre64/lib/amd64 on the library
# path, which the bundled JRE does not have, so its libjsig preload silently does nothing. The
# script itself is not used because it ends in `exit 0` - the container would report success no
# matter how the server died - and because it cannot pass VM args.
export PATH="${SERVER_DIR}/jre64/bin:${PATH}"
export LD_LIBRARY_PATH="${SERVER_DIR}/linux64:${SERVER_DIR}:${SERVER_DIR}/jre64/lib:${LD_LIBRARY_PATH:-}"
export LD_PRELOAD="${LD_PRELOAD:+${LD_PRELOAD}:}${SERVER_DIR}/jre64/lib/libjsig.so"

# Read-write so this shell holds both ends: opening a FIFO read-only blocks until a writer appears,
# and the server would see EOF on stdin as soon as the last writer closed.
console_pipe="$(mktemp -u -t pz-console-XXXXXX)"
mkfifo "${console_pipe}"
exec 3<>"${console_pipe}"
rm -f "${console_pipe}"

cd "${SERVER_DIR}"
./ProjectZomboid64 "${vm_args[@]}" -- "${server_args[@]}" <&3 &
server_pid=$!

# The handler exits the script itself rather than returning: bash re-raises a fatal signal that
# interrupted `wait` once the handler is done, so anything after the wait would never run and a
# stop that did exactly what it was asked would be reported as killed.
shutdown() {
    trap '' TERM INT
    log "saving and stopping the server"
    printf 'save\nquit\n' >&3

    for (( waited = 0; waited < SHUTDOWN_TIMEOUT; waited++ )); do
        if ! kill -0 "${server_pid}" 2> /dev/null; then
            log "the server saved and stopped"
            exit 0
        fi
        sleep 1
    done

    log "the server did not stop within ${SHUTDOWN_TIMEOUT}s, killing it - the world may roll back to the last autosave"
    kill -KILL "${server_pid}" 2> /dev/null || true
    exit 1
}
trap shutdown TERM INT

exit_code=0
wait "${server_pid}" || exit_code=$?
exit "${exit_code}"
