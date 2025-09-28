#!/usr/bin/env bash

# shellcheck source=lib.sh
. "$(dirname "${0}")/lib.sh"

# Read in and convert env vars as needed
OUTPUT_PATH=${1:-/etc/keepalived/keepalived.conf}

# Short circuit
if [ -f "${OUTPUT_PATH}" ]; then
    echo Configuration file at "${OUTPUT_PATH}" already exists, skipping generation.
    exit 0
fi

# Log unset input vars
: "${ROUTER_NETWORK_INTERFACE:?}"
: "${EGRESS_VIP_ADDRESS:?}"
: "${SUBNET_CIDR_BITS:?}"
: "${VIP_UNDERLYING_INTERFACE:?}"

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
    virtual_router_id 52

    virtual_ipaddress {
        # This is the router's primary virtual IP address, and the link to attach it to.
        # This is used for routing client pod egress traffic specifically.
        # MACVLAN is used to avoid issues with arising from stale ARP entries in clients and
        # switches/bridges with learning enabled.
        # noprefixroute is needed to prevent the kernel from adding the link-scoped route automatically.
        # Without this, the route will get appended instead of prepended, and will never be matched.
        # See below for the workaround.
        ${EGRESS_VIP_ADDRESS}/${SUBNET_CIDR_BITS} dev ${VIP_UNDERLYING_INTERFACE} use_vmac noprefixroute
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
        indent 1 notify_${EVENT} "\"/sbin/ip route ${ACTION} ${NETWORK_ADDRESS}/${SUBNET_CIDR_BITS} dev vrrp.52 scope link src ${EGRESS_VIP_ADDRESS}\""
    done
)
}
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
