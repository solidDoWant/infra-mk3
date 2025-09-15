#!/bin/ash

# shellcheck shell=dash
set -eu

# shellcheck source=/dev/null
. "$(dirname "${0}")/set-env-vars.sh"

set -x

PROTOCOLS=${PROTOCOLS:-"tcp udp"}

# The destination IP is set the base IP + the last octet of the local address
LAST_OCTET="$(ip -br addr show dev "${GATEWAY_NETWORK_INTERFACE}" | sed 's/^.*\.\([0-9]\{1,3\}\)\/.*$/\1/')"
PORT_FORWARD_DESTINATION_IP="${PORT_FORWARD_DESTINATION_BASE_IP%.*}.$((${PORT_FORWARD_DESTINATION_BASE_IP##*.} + LAST_OCTET))"

# Rewrite packets that are port-forwarded by the VPN to the destination IP:Port combo
for PORT in ${PORT_FORWARDING_PORTS}; do
    PORT_FORWARD_DESTINATION="${PORT_FORWARD_DESTINATION_IP}:${PORT}"

    for PROTOCOL in ${PROTOCOLS}; do
        iptables -t nat -A PREROUTING -i "${VPN_INTERFACE}" -p "${PROTOCOL}" --dst "${WIREGUARD_ADDRESSES}" --dport "${PORT}" -j DNAT --to-destination "${PORT_FORWARD_DESTINATION}"
    done
done

# Rewrite packets that come in the local interface to the VPN interface with the VPN interface source address, but only if they are not destined for the local machine
# Sending packets for with a source IP within the VPN gateway subnet would result in the destination not knowing how to route the reply packets back
iptables -t nat -A POSTROUTING -o "${VPN_INTERFACE}" --match addrtype ! --dst-type LOCAL,BROADCAST,ANYCAST,MULTICAST -j MASQUERADE

# TODO iptables rule to block traffic from tun0
