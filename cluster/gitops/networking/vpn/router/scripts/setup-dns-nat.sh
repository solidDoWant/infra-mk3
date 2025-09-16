#!/usr/bin/env bash

set -euxo pipefail

: "${KUBE_DNS_SERVICE_IP_ADDRESS?:}"
: "${ROUTER_VIP_ADDRESS?:}"

# This script DNATs DNS requests targeting the normal k8s DNS resolver to the VPN
# DNS resolver. This allows for transparently ensuring that DNS requests go out
# the VPN instead of getting leaked.

for PROTOCOL in tcp udp; do
    iptables -t nat -A PREROUTING -d "${KUBE_DNS_SERVICE_IP_ADDRESS}" -p "${PROTOCOL}" --dport 53 -j DNAT --to-destination "${ROUTER_VIP_ADDRESS}:53"
done
