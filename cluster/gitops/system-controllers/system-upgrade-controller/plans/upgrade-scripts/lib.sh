#!/bin/bash

# Usage:
# 
# ```shell
# extra_plan_checks() { }
# extra_usage_args() { }
# extra_inputs_set() { }
# upgrade() { }
# 
# # shellcheck source=lib.sh
# . "$(dirname "${0}")/lib.sh"
# ```

set -euo pipefail

usage() {
    cat <<- EOF
	Usage: ${0} {plan|upgrade} <node name> <talos version> $(extra_usage_args)
	EOF
    exit 1
}

set_arch() {
    MACHINE_ARCH="$(uname -m)"
    case "${MACHINE_ARCH}" in
        x86_64) ARCH='amd64' ;;
        *) ARCH="${MACHINE_ARCH}" ;;
    esac
}

# TODO create an image with these tools pre-installed
install_deps() {
    echo "Installing talosctl ${TALOS_VERSION} for ${ARCH}..."
    curl -fsSL -o /usr/local/bin/talosctl "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-${ARCH}"
    chmod +x /usr/local/bin/talosctl
}

check_if_drained() {
    echo 'Checking if node has been drained...'

    DRAIN_OUTPUT="$(
        kubectl drain "${NODE_NAME}" \
            --delete-emptydir-data \
            --ignore-daemonsets \
            --dry-run=server \
        2>/dev/null
    )"

    if echo "${DRAIN_OUTPUT}" | grep -q "^node/${NODE_NAME} cordoned"; then
        >&2 echo "Node has not yet been cordoned, failing"
        exit 1
    fi

    if [[ "$(echo "${DRAIN_OUTPUT}" | wc -l)" != 2 ]]; then
        >&2 cat <<- EOF
		Node has not yet been drained, failing
		Remaining pods:
		$(echo "${DRAIN_OUTPUT}" | awk 'NR>2 {print last} {last=$3}')
		EOF
        exit 1
    fi

    echo 'Node has been drained'
}

check_if_healthy() {
    echo 'Checking current node health...'

    talosctl -n 127.0.0.1 health --server=false || FAILED='true'

    if [[ "${FAILED}" != 'true' ]]; then
        echo 'Health check passed'
        return
    fi

    >&2 printf 'Health check failed, '

    if [[ "${IGNORE_UNHEALTH}" == 'true' ]]; then
        >&2 echo 'continuing due to IGNORE_UNHEALTHY=true'
    else
        >&2 echo 'failing'
        exit 1
    fi
}

check_if_image_exists() {
    DOMAIN_NAME="${INSTALLER_IMAGE%%/*}"
    IMAGE_NAME="${INSTALLER_IMAGE#*/}"
    MANIFEST_URL="https://${DOMAIN_NAME}/v2/${IMAGE_NAME}/manifests/${TALOS_VERSION}"

    # shellcheck disable=SC2016
    curl -fsSL "${MANIFEST_URL}" \
        jq -e --arg ARCH "${ARCH}" '.manifests[] | select(.platform.architecture == $ARCH)'
}

plan() {
    echo "Performing pre-upgrade checks..."

    set_arch
    install_deps
    check_if_drained
    extra_plan_checks

    echo "All checks passed"
}

OPERATION="${1}"
[[ -n "${OPERATION}" ]] || usage

extra_inputs_set "${@:4}"

NODE_NAME="${2:-"${NODE_NAME}"}"
[[ -n "${NODE_NAME}" ]] || usage

TALOS_VERSION="${3:-"${TALOS_VERSION}"}"
[[ -n "${TALOS_VERSION}" ]] || usage


case "${OPERATION}" in
    prepare) plan ;;
    upgrade) plan && upgrade ;;
    *) usage ;;
esac