#!/bin/ash

# shellcheck shell=dash
set -eu

# shellcheck source=/dev/null
. "$(dirname "${0}")/set-env-vars.sh"

set -x

# Rewrite packets that are port-forwarded by the VPN to the destination IP:Port combo
for PORT in ${PORT_FORWARDING_PORTS}; do
    for PROTOCOL in ${PROTOCOLS}; do
        iptables -t nat -A PREROUTING -i "${VPN_INTERFACE}" -p "${PROTOCOL}" --dst "${WIREGUARD_ADDRESSES}" --dport "${PORT}" -j DNAT --to-destination "${PORT_FORWARD_DESTINATION_IP}":"${PORT}"
    done
done

# Rewrite the source IP of outgoing packets to the local interface's IP
for PORT in ${PORT_FORWARDING_PORTS}; do
    for PROTOCOL in ${PROTOCOLS}; do
        iptables -t nat -A POSTROUTING -o "${LOCAL_INTERFACE}"  -p "${PROTOCOL}" --dst "${PORT_FORWARD_DESTINATION_IP}" --dport "${PORT}" -j MASQUERADE
    done
done

# Rewrite packets that come in the local interface to the VPN interface with the VPN interface source address, but only if they are not destined for the local machine
# Sending packets for with a source IP within the VPN gateway subnet would result in the destination not knowing how to route the reply packets back
iptables -t nat -A POSTROUTING -o "${VPN_INTERFACE}" --match addrtype ! --dst-type LOCAL,BROADCAST,ANYCAST,MULTICAST -j MASQUERADE
