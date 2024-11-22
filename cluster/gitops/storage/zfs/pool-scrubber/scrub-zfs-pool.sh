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

install_kubectl() {
    echo "Installing kubectl..."
    apt update
    apt install --no-install-recommends -y curl ca-certificates
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')"
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)"
    VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${VERSION}/bin/${KERNEL}/${PRETTY_ARCH}/kubectl"
    chmod +x /usr/local/bin/kubectl
    echo "Installed kubectl ${VERSION}"
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
install_kubectl

# Scrub
echo "Current zpool status:"
run_rootfs_cmd zpool status -v

echo "Starting scrub..."
run_rootfs_cmd zpool scrub -w "${POOL_NAME}" || true
echo "Scrub complete!"

echo "Post-scrub status:"
run_rootfs_cmd zpool status -v

# Cleanup
kubectl label --overwrite node "${NODE_NAME}" 'zfs.home.arpa/node.local-storage-scrub-'
