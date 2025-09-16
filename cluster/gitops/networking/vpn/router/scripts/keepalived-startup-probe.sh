#!/usr/bin/env bash

set -euo pipefail

# This script is used as a startup probe for keepalived. It checks the following:
# 1. No routers are in FAULT state
# 2. All health checkers have ran at least once (whether they pass or fail)

# Send a signal to keepalived to dump its state to /tmp
kill -USR1 "$(cat /var/run/keepalived/keepalived.pid)"

# Check that no routers are in FAULT state
FAULT_ENTRIES="$(cat /tmp/keepalived.data | grep 'State = FAULT' || true)"
FAULT_ENTRY_COUNT="$(printf "%s" "${FAULT_ENTRIES}" | wc -l)"
if [ "${FAULT_ENTRY_COUNT}" -gt 0 ]; then
    >&2 echo "${FAULT_ENTRY_COUNT} VRRP instances are in FAULT state"
    exit 1
fi

# Check that all health checkers have ran at least once
NOT_RAN_CHECKER_ENTRIES="$(cat /tmp/keepalived_check.data | grep 'Has run = no' || true)"
NOT_RAN_CHECKER_ENTRY_COUNT="$(printf "%s" "${NOT_RAN_CHECKER_ENTRIES}" | wc -l)"
if [ "${NOT_RAN_CHECKER_ENTRY_COUNT}" -gt 0 ]; then
    >&2 echo "${NOT_RAN_CHECKER_ENTRY_COUNT} health checkers have not ran at least once"
    exit 1
fi
