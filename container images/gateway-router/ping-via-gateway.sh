#!/bin/bash
set -euo pipefail

# This sends an ICMP echo request to the target IP, via the specified interface and gateway.
# This works by setting the destination MAC address to that of the next hop, and sending the
# packet out the specified interface. This ignores the routing table, ensuring that the packet
# goes to the desired next hop.

if [ "${#}" -ne 3 ]; then
    >&2 echo "Usage: ${0} <GATEWAY_IP> <SOURCE_INTERFACE> <TARGET_IP>"
    exit 1
fi

GATEWAY_ADDRESS="$(nmap -sn -n "${1}" | grep 'MAC Address' | cut -d' ' -f3)"
if [ -z "${GATEWAY_ADDRESS}" ]; then
    >&2 echo "Could not determine gateway address"
    exit 1
fi

exec nping --icmp --count 1 --dest-mac "${GATEWAY_ADDRESS}" --interface "${2}" "${3}"
