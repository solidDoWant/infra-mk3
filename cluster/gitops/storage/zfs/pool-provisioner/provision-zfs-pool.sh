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

load_annotation_vars() {
    install_kubectl
    POOL_DRIVE_MATCHER="$(
        kubectl get node "${NODE_NAME}" -o \
            jsonpath='{.metadata.annotations.zfs\.home\.arpa/node\.pool-drive-matcher}'
    )"
    mapfile -t POOL_DRIVE_PATHS < <(find "${ROOTFS_PATH}/dev" -wholename "$(realpath "${ROOTFS_PATH}/${POOL_DRIVE_MATCHER}")")
    echo "Found drives '${POOL_DRIVE_PATHS[*]}' matching '${POOL_DRIVE_MATCHER}'"

    if [[ "${#POOL_DRIVE_PATHS[@]}" -lt 1 ]]; then
        fatal "Pool drive matcher label value '${POOL_DRIVE_MATCHER}' did not match one or more device"
    fi
}

check_env_vars() {
    for REQUIRED_ENV_VAR in "${REQUIRED_ENV_VARS[@]}"; do
        [[ -n "${!REQUIRED_ENV_VAR}" ]] || usage
    done
}

check_module() {
    grep -q '^zfs ' < "${ROOTFS_PATH}/proc/modules" || \
        fatal "ZFS module not loaded"
}

run_rootfs_cmd() {
    chroot "${ROOTFS_PATH}" "${@}"
}

label_node() {
    # Prevent the pool from being re-initialized
    kubectl label node "${NODE_NAME}" 'zfs.home.arpa/node.local-storage-deployed=true'
}

check_pool() {
    if ! run_rootfs_cmd zpool list "${POOL_NAME}"; then
        return
    fi

    label_node
    fatal "Pool already exists"
}

check_devices() {
    for POOL_DRIVE_PATH in "${POOL_DRIVE_PATHS[@]}"; do
        [[ -b "${POOL_DRIVE_PATH}" ]] || \
            fatal "Pool drive '${POOL_DRIVE_PATH}' does not exist or is not a block device"
    done
}

check_fs() {
    for POOL_DRIVE_PATH in "${POOL_DRIVE_PATHS[@]}"; do
        ! blkid "${POOL_DRIVE_PATH}" -o export | grep -q TYPE || \
            fatal "Found existing filesystem on drive"
    done
}

run_checks() {
    echo "Starting checks..."
    check_env_vars
    load_annotation_vars
    check_module
    check_pool
    check_devices
    check_fs
    echo "All checks passed"
}

run_checks

# cSpell:disable
echo "Provisioning pool..."
run_rootfs_cmd zpool create \
    -f \
    -o ashift=12 \
    -O acltype=posixacl \
    -O compression=lz4 \
    -O dnodesize=auto \
    -O relatime=off \
    -O atime=off \
    -O xattr=sa \
    -O "mountpoint=/var/mnt/${POOL_NAME}" \
    "${POOL_NAME}" \
    "${POOL_DRIVE_PATH[@]#${ROOTFS_PATH}}"
label_node
echo "Provisioning complete"
run_rootfs_cmd zpool list