#!/usr/bin/env bash

set -euo pipefail

# Read in and convert env vars as needed
OUTPUT_PATH=${1:-/etc/keepalived/keepalived.conf}
read -ra INGRESS_PORTS <<< "${INGRESS_PORTS}"

# Short circuit
if [ -f "${OUTPUT_PATH}" ]; then
    echo Configuration file at "${OUTPUT_PATH}" already exists, skipping generation.
    exit 0
fi

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

# Helper functions
# Indent text by a number of tabs (4 spaces each)
indent() {
    TABS="${1}"
    shift
    TEXT="${*}"

    printf "%$(( 4 * TABS ))s%s\n" "" "${TEXT}"
}

# Given an IP address within a subnet, return the network address of that subnet.
get_network_address() {
    IP_ADDRESS="${1}"
    CIDR_BITS="${2}"

    IFS=. read -ra octets <<< "${IP_ADDRESS}"
    NETWORK_ADDRESS_OCTETS=()
    REMAINING_BITS="${CIDR_BITS}"
    
    for i in {0..3}; do
        if [ "${REMAINING_BITS}" -le 0 ]; then
            NETWORK_ADDRESS_OCTETS+=("0")
            continue
        fi

        BITS_IN_OCTET=$(( REMAINING_BITS < 8 ? REMAINING_BITS : 8 ))
        MASK=$(( 256 - 2**(8 - BITS_IN_OCTET) ))
        NETWORK_ADDRESS_OCTETS+=("$(( octets[i] & MASK ))")
        REMAINING_BITS=$(( REMAINING_BITS - 8 ))
    done

    (IFS=.; printf "%s" "${NETWORK_ADDRESS_OCTETS[*]}")
}

# Give an address e.g. A.B.C.D and a count N, generate addresses A.B.C.(D) through A.B.C.(D+N-1)
# Optionally, an offset can be provided to add to the starting octet.
generate_addresses() {
    FIRST_ADDRESS="${1}"
    COUNT="${2}"
    OFFSET="${3:-0}"

    BASE_ADDRESS="${FIRST_ADDRESS%.*}"
    START_OCTET="$((${FIRST_ADDRESS##*.} + OFFSET))"
    END_OCTET="$((START_OCTET + COUNT - 1))"

    ADDRESSES=()
    for OCTET in $(seq "${START_OCTET}" "${END_OCTET}"); do
        ADDRESSES+=("${BASE_ADDRESS}.${OCTET}")
    done

    echo "${ADDRESSES[*]}"
}

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

    # Sync the IPVS state between all router pods.
    # Note that to prevent thrashing, client connections will need to send a couple of packets
    # back and forth before the daemon will sync the state with backup routers. This can be
    # tuned via \`sysctl net.ipv4.vs.sync_threshold=<desired min packet count>\`.
    lvs_sync_daemon ${ROUTER_NETWORK_INTERFACE}

    # Drop any existing tracked connections on startup. This is needed in case the container
    # is restarted, so that stale entries are purged. They will be synced back from the master
    # router.
    lvs_flush
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
$(
    NETWORK_ADDRESS="$(get_network_address "${EGRESS_VIP_ADDRESS}" "${SUBNET_CIDR_BITS}")"  # netlink won't accept a non-network address here
    for EVENT in master backup fault stop; do
        test "${EVENT}" == "master" && ACTION="prepend" || ACTION="del"
        indent 1 notify_${EVENT} "\"/sbin/ip route ${ACTION} ${NETWORK_ADDRESS}/${SUBNET_CIDR_BITS} dev vrrp.51 scope link src ${EGRESS_VIP_ADDRESS}\""
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
            indent 1 "# Talos 1.11 does not currently have the config flag for maglev hashing enabled. See"
            indent 1 "# https://github.com/siderolabs/pkgs/issues/1326 for details. Disable this until it is fixed."
            indent 1 "# Use maglev hashing to ensure that connections from the same client IP get routed to the same backend."
            indent 1 "# This should provide consistent hashing with minimal disruption when backends are added/removed."
            indent 1 "# This does not consider the source port number, so multiple connections from a single host will go to"
            indent 1 "# the backend. This is an application-dependent tradeoff between connection stickiness and throughput."
            indent 1 "# To include the source port in the hash, enable \`mh-port\` option."
            indent 1 "# lb_algo mh"
            indent 1 "# If the desired backend is unavailable, try to fall back to another."
            indent 1 "# Another benefit is that if a backend wants to gracefully stop, it can just stop accepting new"
            indent 1 "# connections, while finishing existing ones, without a disruption."
            indent 1 "# mh-fallback"
            indent 1 "# Use source hashing until maglev hashing is available (see above)."
            indent 1 lb_algo sh
            indent 1 sh-fallback
            indent 1 lb_kind NAT
            indent 1 "protocol ${PROTOCOL}"
            indent 0

            # A set of IP addresses is allocated for client pods that accept traffic from a specific port.
            # Define a real server for each of these IP addresses.
            RS_OCTET_START=$((INGRESS_PORT_IDX * CLIENT_INGRESS_COUNT_PER_PORT))
            for CLIENT_INGRESS_IP in $(generate_addresses "${CLIENT_INGRESS_IP_START}" "${CLIENT_INGRESS_COUNT_PER_PORT}" "${RS_OCTET_START}"); do
                indent 1 "real_server ${CLIENT_INGRESS_IP} ${INGRESS_PORT} {"
                case "${PROTOCOL}" in
                    TCP) CHECK_TYPE="TCP" ;;
                    UDP) CHECK_TYPE="PING" ;;
                    *) 2>&1 echo "Error: Unknown protocol '${PROTOCOL}'" && exit 1 ;;
                esac
                indent 2 "${CHECK_TYPE}_CHECK {}"
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
