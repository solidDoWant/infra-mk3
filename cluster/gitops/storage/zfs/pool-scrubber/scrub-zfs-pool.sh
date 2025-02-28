#!/bin/bash

set -euo pipefail

fatal() {
    >&2 echo "$@"
    exit 1
}

REQUIRED_ENV_VARS=(NODE_NAME ROOTFS_PATH POOL_NAME)
usage() {
    USAGE_MSG="Usage: "
    for REQUIRED_ENV_VAR in "${REQUIRED_ENV_VARS[@]}"; do
        USAGE_MSG+="${REQUIRED_ENV_VAR}=... "
    done
    USAGE_MSG+="$0"

    fatal "${USAGE_MSG}"
}

check_env_vars() {
    for REQUIRED_ENV_VAR in "${REQUIRED_ENV_VARS[@]}"; do
        [[ -n "${!REQUIRED_ENV_VAR}" ]] || usage
    done
}

run_rootfs_cmd() {
    chroot "${ROOTFS_PATH}" "${@}"
}

# Setup
check_env_vars

# Scrub
echo "Current zpool status:"
run_rootfs_cmd zpool status -v

echo "Starting scrub..."
run_rootfs_cmd zpool scrub -w "${POOL_NAME}" || true
echo "Scrub complete!"

echo "Post-scrub status:"
run_rootfs_cmd zpool status -v
sleep 60

# Cleanup
kubectl label --overwrite node "${NODE_NAME}" 'zfs.home.arpa/node.local-storage-scrub-'
