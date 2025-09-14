#!/bin/ash

# shellcheck shell=dash
set -eu

# shellcheck source=/dev/null
. "$(dirname "${0}")/set-env-vars.sh"

set -x

PROTOCOLS=${PROTOCOLS:-"tcp udp"}

# The destination IP address is the base IP + the pod index
PORT_FORWARD_DESTINATION_IP="${PORT_FORWARD_DESTINATION_BASE_IP%.*}.$((${PORT_FORWARD_DESTINATION_BASE_IP##*.} + ${POD_INDEX}))"

# Assign an IP address to the gateway network interface based on the pod index
# TODO remove this after some testing and move it back into the NAD
LOCAL_GATEWAY_NETWORK_IP="${LOCAL_GATEWAY_NETWORK_IP_PREFIX}.${POD_INDEX}"
ip addr add "${LOCAL_GATEWAY_NETWORK_IP}/${LOCAL_GATEWAY_NETWORK_SUBNET_BITS}" dev "${GATEWAY_NETWORK_INTERFACE}"

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
