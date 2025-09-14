#!/usr/bin/env bash

# shellcheck source=lib.sh
. "$(dirname "${0}")/lib.sh"

# Log unset input vars
: "${GATEWAY_COUNT:?}"
: "${GATEWAY_IP_START:?}"
: "${INGRESS_VIP_START:?}"

mark_for_gateway_number() {
    GATEWAY_NUM="${1}"
    # 0x1900 = 6400 in base 10. Because the two least significant digits are zero in both bases, this makes it easier to visually match the values between `ip rule` and `iptables-save`.
    echo "$((0x1900 + GATEWAY_NUM))"
}

log_command() {
    echo "+ $*"
    "$@"
}

# 1. Mark connections originating from each gateway (as determined via the gateway-specific destination addresses) with a gateway-specific fwmark.
read -ra INGRESS_VIP_ADDRESSES <<< "$(generate_addresses "${INGRESS_VIP_START}" "${GATEWAY_COUNT}")"
for GATEWAY_NUM in "${!INGRESS_VIP_ADDRESSES[@]}"; do
    INGRESS_VIP_ADDRESS="${INGRESS_VIP_ADDRESSES["${GATEWAY_NUM}"]}"
    GATEWAY_FWMARK="$(mark_for_gateway_number "${GATEWAY_NUM}")"

    # This mark is saved to the entire connection, not just the specific packet. It can later be restored to outbound packets that are part of the same connection.
    log_command iptables -t mangle -A PREROUTING -d "${INGRESS_VIP_ADDRESS}" -m conntrack --ctstate NEW -j CONNMARK --set-mark "${GATEWAY_FWMARK}"
done

# 2. Restore the connection mark to the packet mark for routing decisions on return traffic
log_command iptables -t mangle -A PREROUTING -m conntrack --ctstate ESTABLISHED,RELATED -j CONNMARK --restore-mark

# 3. Route outbound packets for connections originating from the gateway back to the same gateway.
read -ra GATEWAY_ADDRESSES <<< "$(generate_addresses "${GATEWAY_IP_START}" "${GATEWAY_COUNT}")"
for GATEWAY_NUM in "${!GATEWAY_ADDRESSES[@]}"; do
    GATEWAY_ADDRESS="${GATEWAY_ADDRESSES["${GATEWAY_NUM}"]}"
    GATEWAY_TABLE="$((50 + GATEWAY_NUM))"
    GATEWAY_RULE_PRIORITY="$((1000 + GATEWAY_NUM))"
    GATEWAY_FWMARK="$(mark_for_gateway_number "${GATEWAY_NUM}")"

    # The actual values of these vars are not critical, they just need to be unique per gateway and not conflict with
    # existing resources in the network namespace.
    log_command ip route add default via "${GATEWAY_ADDRESS}" table "${GATEWAY_TABLE}"
    log_command ip rule del fwmark "${GATEWAY_FWMARK}" table "${GATEWAY_TABLE}" priority "${GATEWAY_RULE_PRIORITY}" 2>/dev/null || true
    log_command ip rule add fwmark "${GATEWAY_FWMARK}" table "${GATEWAY_TABLE}" priority "${GATEWAY_RULE_PRIORITY}"
done
