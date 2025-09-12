#!/bin/ash

# shellcheck shell=dash
set -eu

# shellcheck source=/dev/null
. "$(dirname "${0}")/set-env-vars.sh"

set -x

PROTOCOLS=${PROTOCOLS:-"tcp udp"}

# Rewrite packets that are port-forwarded by the VPN to the destination IP:Port combo
for PORT in ${PORT_FORWARDING_PORTS}; do
    DESTINATION_IP="${PORT_FORWARD_DESTINATION_IP_PREFIX}.${LAST_OCTET}"

    for PROTOCOL in ${PROTOCOLS}; do
        iptables -t nat -A PREROUTING -i "${VPN_INTERFACE}" -p "${PROTOCOL}" --dst "${WIREGUARD_ADDRESSES}" --dport "${PORT}" -j DNAT --to-destination "${DESTINATION_IP}":"${PORT}"
    done
done

# Rewrite the source IP of outgoing packets to the local interface's IP
LAST_OCTET=1
for PORT in ${PORT_FORWARDING_PORTS}; do
    DESTINATION_IP="${PORT_FORWARD_DESTINATION_IP_PREFIX}.${LAST_OCTET}"

    for PROTOCOL in ${PROTOCOLS}; do
        iptables -t nat -A POSTROUTING -o "${GATEWAY_NETWORK_INTERFACE}"  -p "${PROTOCOL}" --dst "${DESTINATION_IP}" --dport "${PORT}" -j MASQUERADE
    done

    LAST_OCTET=$((LAST_OCTET + 1))
done

# Rewrite packets that come in the local interface to the VPN interface with the VPN interface source address, but only if they are not destined for the local machine
# Sending packets for with a source IP within the VPN gateway subnet would result in the destination not knowing how to route the reply packets back
iptables -t nat -A POSTROUTING -o "${VPN_INTERFACE}" --match addrtype ! --dst-type LOCAL,BROADCAST,ANYCAST,MULTICAST -j MASQUERADE

# TODO iptables rule to block traffic from tun0
