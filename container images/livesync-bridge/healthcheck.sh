#!/bin/sh
# Liveness check for the bridge's heartbeat file. main.ts rewrites it every 10s; a stale
# file means a wedged event loop, and restartWorthy means a peer asked for a restart.
set -eu
HEALTH_FILE="${LSB_HEALTH_FILE:-/tmp/lsb-health.json}"
# Allow the first beat time to land after start.
[ -f "${HEALTH_FILE}" ] || exit 0
[ -n "$(find "${HEALTH_FILE}" -mmin -1)" ] || { echo "heartbeat is stale"; exit 1; }
if grep -q '"restartWorthy":true' "${HEALTH_FILE}"; then
    echo "a peer reported a restart-worthy failure"
    exit 1
fi
