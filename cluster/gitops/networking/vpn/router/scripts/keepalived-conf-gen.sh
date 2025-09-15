#!/usr/bin/env bash

# shellcheck source=lib.sh
. "$(dirname "${0}")/lib.sh"

OUTPUT_PATH=${1:-/etc/keepalived/keepalived.conf}

# Log unset input vars
: "${INGRESS_PORTS:?}"
: "${ROUTER_NETWORK_INTERFACE:?}"
: "${EGRESS_VIP_ADDRESS:?}"
: "${SUBNET_CIDR_BITS:?}"
: "${VIP_UNDERLYING_INTERFACE:?}"
: "${GATEWAY_COUNT:?}"
: "${INGRESS_VIP_START:?}"
: "${CLIENT_INGRESS_IP_START:?}"
: "${CLIENT_INGRESS_COUNT_PER_PORT:?}"

indent() {
    TABS="${1}"
    shift
    TEXT="${*}"

    printf "%$(( 4 * TABS ))s%s\n" "" "${TEXT}"
}

read -ra INGRESS_PORTS <<< "${INGRESS_PORTS}"

# I really tried to just generate this via the built-in keepalived templating
# tools, but it's just too rigid and difficult to debug. If nothing else, when
# this approach is misconfigured, it will be dumped to stdout for debugging.

echo "Generating keepalived configuration in ${OUTPUT_PATH}"
cat << EOF > "${OUTPUT_PATH}"
global_defs {
    # Log VRRP advertisements for virtual router IDs not configured.
    log_unknown_vrids

    # This is needed to allow keepalived to run the VRRP notify scripts.
    enable_script_security
    script_user root root

    # Error if the include file is missing or cannot be read.
    include_check
}

vrrp_instance router {
    # Start all instance in BACKUP mode. They'll elect a master among themselves.
    state BACKUP
    # Use this interface for VRRP advertisements. If a pod is compromised, they won't be able to
    # affect the VRRP state of the routers, because the routers communicate over their own network.
    interface ${ROUTER_NETWORK_INTERFACE}
    # This value is arbitrary, but must be the same for all pods.
    virtual_router_id 51

    virtual_ipaddress {
        # This is the router's primary virtual IP address, and the link to attach it to.
        # This is used for routing client pod egress traffic specifically.
        # MACVLAN is used to avoid issues with arising from stale ARP entries in clients and
        # switches/bridges with learning enabled.
        # noprefixroute is needed to prevent the kernel from adding the link-scoped route automatically.
        # Without this, the route will get appended instead of prepended, and will never be matched.
        # See below for the workaround.
        ${EGRESS_VIP_ADDRESS}/${SUBNET_CIDR_BITS} dev ${VIP_UNDERLYING_INTERFACE} use_vmac noprefixroute

        # These are additional addresses, one for each gateway, that gateways should send ingress traffic to.
        # One per gateway is used so that the router can tell which gateway the traffic came from, and route return
        # traffic back to the correct gateway. Without this, the router tie the connection state back to the gateway
        # that originated the traffic, which would result in the traffic being sent to a random gateway.
$(
    for INGRESS_VIP in $(generate_addresses "${INGRESS_VIP_START}" "${GATEWAY_COUNT}"); do
        indent 2 "${INGRESS_VIP}/${SUBNET_CIDR_BITS}" dev "${VIP_UNDERLYING_INTERFACE}" use_vmac noprefixroute
    done
)
    }

    # Add/del a route to the local subnet with the VIP as the source. This will cause packets to use the VIP
    # as the source address when routing to the local subnet. This is needed to make sure that ICMP messages
    # (e.g. "fragmentation needed" or "time exceeded") are sent from the VIP address.
    #
    # For some weird reason keepalived tries to process virtual_routes prior to brining the MACVLAN interface up,
    # which causes the route entries to fail. This causes keepalived to move to "FAULT" state.
    # To work around this, add the routes manually using the notify scripts.
    # TODO this current config will probably produce a separate MACVLAN interface for each VIP address - fix this if it does
$(
    for EVENT in master backup fault stop; do
        indent 1 notify_${EVENT} "\"/sbin/ip route ${EVENT} ${EGRESS_VIP_ADDRESS}/${SUBNET_CIDR_BITS} dev vrrp.51 scope link src ${EGRESS_VIP_ADDRESS}\""
    done
)
}

$(
    for INGRESS_PORT_IDX in "${!INGRESS_PORTS[@]}"; do
        INGRESS_PORT="${INGRESS_PORTS[INGRESS_PORT_IDX]}"

        # Define a virtual server group per port. This will include all ingress VIP addresses.
        VS_GROUP_NAME="virtual_servers_for_port_${INGRESS_PORT}"
        indent 0 virtual_server_group "${VS_GROUP_NAME} {"

        for INGRESS_VIP in $(generate_addresses "${INGRESS_VIP_START}" "${GATEWAY_COUNT}"); do
            indent 1 "${INGRESS_VIP} ${INGRESS_PORT}"
        done

        indent 0 "}"
        indent 0

        # Define a pair of TCP and UDP virtual servers per port.
        for PROTOCOL in TCP UDP; do
            indent 0 "virtual_server group ${VS_GROUP_NAME} {"
            indent 1 lb_algo lc
            indent 1 lb_kind NAT
            indent 1 "protocol ${PROTOCOL}"
            indent 0

            # A set of IP addresses is allocated for client pods that accept traffic from a specific port.
            # Define a real server for each of these IP addresses.
            RS_OCTET_START=$((INGRESS_PORT_IDX * CLIENT_INGRESS_COUNT_PER_PORT))
            for CLIENT_INGRESS_IP in $(generate_addresses "${CLIENT_INGRESS_IP_START}" "${CLIENT_INGRESS_COUNT_PER_PORT}" "${RS_OCTET_START}"); do
                indent 1 "real_server ${CLIENT_INGRESS_IP} ${INGRESS_PORT} {"
                indent 2 "PING_CHECK {}"
                indent 1 "}"
            done

            indent 0 "}"
            indent 0
        done
    done
)
EOF

echo "Generated keepalived configuration:"
cat "${OUTPUT_PATH}"

echo
echo "Checking keepalived configuration in ${OUTPUT_PATH}"
if ! keepalived "--use-file=${OUTPUT_PATH}" --config-test; then
    2>&1 echo "Error: keepalived configuration test failed"
    exit 1
fi
echo "Keepalived configuration test passed"
