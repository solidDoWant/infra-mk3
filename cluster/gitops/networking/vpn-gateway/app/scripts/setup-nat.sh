#!/bin/ash

# shellcheck shell=dash
set -eux

# Rewrite packets that are port-forwarded by the VPN to the destination IP:Port combo
for PORT in ${PORT_FORWARDING_PORTS}; do
    for PROTOCOL in ${PROTOCOLS}; do
        iptables -t nat -A PREROUTING -i "${VPN_INTERFACE}" -p "${PROTOCOL}" --match addrtype ! --dst-type LOCAL --dport "${PORT}" -j DNAT --to-destination "${PORT_FORWARD_DESTINATION_IP}":"${PORT}"
    done
done

# Rewrite the source IP of outgoing packets to the local interface's IP
for PORT in ${PORT_FORWARDING_PORTS}; do
    for PROTOCOL in ${PROTOCOLS}; do
        iptables -t nat -A POSTROUTING -o "${LOCAL_INTERFACE}"  -p "${PROTOCOL}" --dst "${PORT_FORWARD_DESTINATION_IP}" --dport "${PORT}" -j MASQUERADE
    done
done

# Rewrite packets that come in the local interface to the VPN interface with the VPN interface source address, but only if they are not destined for the local machine
# TODO this is not needed as Cilium does not support routing to service addresses. When/if https://github.com/cilium/cilium/issues/40146 is implemented,
# this can be enabled, and applications pods can route traffic via the VPN gateway by running `ip route add <VPN_SERVICE_IP> dev eth0 scope link && ip route add default via <VPN_SERVICE_IP> dev eth0`
# iptables -t nat -A POSTROUTING -o "${VPN_INTERFACE}" --match addrtype ! --dst-type LOCAL,BROADCAST,ANYCAST,MULTICAST -j MASQUERADE
