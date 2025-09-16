#!/usr/bin/env bash

set -euo pipefail

# Send a signal to keepalived to dump its state to /tmp
kill -USR1 "$(cat /var/run/keepalived/keepalived.pid)"

# Check that no routers are in FAULT state
FAULT_ENTRIES="$(cat /tmp/keepalived.data | grep 'State = FAULT' || true)"
FAULT_ENTRY_COUNT="$(printf "%s" "${FAULT_ENTRIES}" | wc -l)"
if [ "${FAULT_ENTRY_COUNT}" -gt 0 ]; then
    >&2 echo "${FAULT_ENTRY_COUNT} VRRP instances are in FAULT state"
    exit 1
fi
