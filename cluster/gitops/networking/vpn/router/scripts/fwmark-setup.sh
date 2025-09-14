#!/usr/bin/env bash

set -euo pipefail

# Log unset input vars
: "${INGRESS_VIP_PREFIX:?}"
: "${INGRESS_VIP_OCTET_START:?}"
: "${INGRESS_VIP_OCTET_END:?}"

: "${GATEWAY_IP_PREFIX:?}"
: "${GATEWAY_IP_OCTET_START:?}"
: "${GATEWAY_IP_OCTET_END:?}"

mark_for_gateway_number() {
    GATEWAY_NUM="${1}"
    # 0x1900 = 6400 in base 10. Because the two least significant digits are zero in both bases, this makes it easier to visually match the values between `ip rule` and `iptables-save`.
    echo $((0x1900 + GATEWAY_NUM))
}

log_command() {
    echo "+ $*"
    "$@"
}

# Input validation
GATEWAY_IP_COUNT=$((GATEWAY_IP_OCTET_END - GATEWAY_IP_OCTET_START + 1))
INGRESS_VIP_COUNT=$((INGRESS_VIP_OCTET_END - INGRESS_VIP_OCTET_START + 1))
if [ "${GATEWAY_IP_COUNT}" -ne "${INGRESS_VIP_COUNT}" ]; then
    >&2 echo "Error: The number of gateway IPs (${GATEWAY_IP_COUNT}) must match the number of ingress VIPs (${INGRESS_VIP_COUNT})."
    exit 1
fi
GATEWAY_COUNT="${GATEWAY_IP_COUNT}"

# 1. Mark connections originating from each gateway (as determined via the gateway-specific destination addresses) with a gateway-specific fwmark.
for GATEWAY_NUM in $(seq 0 "$((GATEWAY_COUNT - 1))"); do
    INGRESS_VIP_OCTET=$((INGRESS_VIP_OCTET_START + GATEWAY_NUM))
    INGRESS_VIP_ADDRESS="${INGRESS_VIP_PREFIX}.${INGRESS_VIP_OCTET}"
    GATEWAY_FWMARK="$(mark_for_gateway_number "${GATEWAY_NUM}")"

    # This mark is saved to the entire connection, not just the specific packet. It can later be restored to outbound packets that are part of the same connection.
    log_command iptables -t mangle -A PREROUTING -d "${INGRESS_VIP_ADDRESS}" -m conntrack --ctstate NEW -j CONNMARK --set-mark "${GATEWAY_FWMARK}"
done

# 2. Restore the connection mark to the packet mark for routing decisions on return traffic
log_command iptables -t mangle -A PREROUTING -m conntrack --ctstate ESTABLISHED,RELATED -j CONNMARK --restore-mark

# 3. Route outbound packets for connections originating from the gateway back to the same gateway.
for GATEWAY_NUM in $(seq 0 "$((GATEWAY_COUNT - 1))"); do
    GATEWAY_IP_OCTET=$((GATEWAY_IP_OCTET_START + GATEWAY_NUM))
    GATEWAY_ADDRESS="${GATEWAY_IP_PREFIX}.${GATEWAY_IP_OCTET}"
    GATEWAY_TABLE="$((50 + GATEWAY_NUM))"
    GATEWAY_RULE_PRIORITY="$((1000 + GATEWAY_NUM))"
    GATEWAY_FWMARK="$(mark_for_gateway_number "${GATEWAY_NUM}")"

    # The actual values of these vars are not critical, they just need to be unique per gateway and not conflict with
    # existing resources in the network namespace.
    log_command ip route add default via "${GATEWAY_ADDRESS}" table "${GATEWAY_TABLE}"
    log_command ip rule del fwmark "${GATEWAY_FWMARK}" table "${GATEWAY_TABLE}" priority "${GATEWAY_RULE_PRIORITY}" 2>/dev/null || true
    log_command ip rule add fwmark "${GATEWAY_FWMARK}" table "${GATEWAY_TABLE}" priority "${GATEWAY_RULE_PRIORITY}"
done
