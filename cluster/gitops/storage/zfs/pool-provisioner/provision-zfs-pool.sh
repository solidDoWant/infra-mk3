#!/bin/bash

set -euo pipefail

warn() {
    >&2 echo "$@"
}

fatal() {
    warn "$@"
    exit 1
}

REQUIRED_ENV_VARS=(NODE_NAME ROOTFS_PATH POOL_NAME CONFIG_MAP_NAME)
usage() {
    USAGE_MSG="Usage: "
    for REQUIRED_ENV_VAR in "${REQUIRED_ENV_VARS[@]}"; do
        USAGE_MSG+="${REQUIRED_ENV_VAR}=... "
    done
    USAGE_MSG+="$0"

    fatal "${USAGE_MSG}"
}

load_annotation_vars() {
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
    check_devices
    check_fs
    echo "All checks passed"
}

provision_pool() {
    echo "Provisioning pool '${POOL_NAME}'..."
    if run_rootfs_cmd zpool list "${POOL_NAME}" > /dev/null; then
        warn "Pool already exists"
        return
    fi

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
}

provision_dataset() {
    DATASET="${1}"

    echo "Provisioning dataset '${DATASET}'..."
    if run_rootfs_cmd zfs list "${DATASET}" > /dev/null; then
        warn "Dataset '${DATASET}' already exists"
        return
    fi

    run_rootfs_cmd zfs create "${DATASET}"
}

provision_datasets() {
    # This cross-cutting logic isn't great, but I'm not sure where else to put it
    DATASETS=(
        ""
        "/postgres"
        "/victoria-metrics"
        "/victoria-metrics/vmstorage"
        "/victoria-metrics/anomaly"
    )
    DATASETS=("${DATASETS[@]/#/${POOL_NAME}/openebs}")

    for DATASET in "${DATASETS[@]}"; do
        provision_dataset "${DATASET}"
    done
}

provision() {
    provision_pool
    provision_datasets
}

configure_dataset() {
    DATASET="${1}"
    PROPERTY="${2}"
    VALUE="${3}"

    echo "Setting dataset '${DATASET}' property '${PROPERTY}' to '${VALUE}'..."
    CURRENT_VALUE="$(run_rootfs_cmd zfs get -H -o value "${PROPERTY}" "${DATASET}")" || \
        fatal "Failed to get property '${PROPERTY}' on dataset '${DATASET}' (exit code '${?}')"

    if [[ "${CURRENT_VALUE}" == "${VALUE}" ]]; then
        warn "Property '${PROPERTY}' to '${VALUE}' already set on dataset '${DATASET}'"
        return
    fi

    run_rootfs_cmd zfs set "${PROPERTY}=${VALUE}" "${DATASET}"
}

configure_datasets() {
    # cSpell:words primarycache
    configure_dataset "${POOL_NAME}/openebs/postgres" "primarycache" "metadata"
}

finalize() {
    echo "Provisioning complete"
    run_rootfs_cmd zpool list
    run_rootfs_cmd zfs list

    kubectl label --overwrite node "${NODE_NAME}" 'zfs.home.arpa/node.local-storage-deployed=true'
    sleep 60    # Must sleep before labeling or k8s will kill the pod first
    # Prevent the pool from being re-initialized unless there is a change to this script
    kubectl label --overwrite node "${NODE_NAME}" "zfs.home.arpa/node.local-storage-config-map=${CONFIG_MAP_NAME}"
}

run_checks
provision
configure_datasets
finalize
