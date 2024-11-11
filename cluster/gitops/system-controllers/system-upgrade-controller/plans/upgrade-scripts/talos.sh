#!/bin/bash

# shellcheck disable=SC2317
check_if_image_exists() {
    DOMAIN_NAME="${INSTALLER_IMAGE%%/*}"
    IMAGE_NAME="${INSTALLER_IMAGE#*/}"
    MANIFEST_URL="https://${DOMAIN_NAME}/v2/${IMAGE_NAME}/manifests/${TALOS_VERSION}"

    # shellcheck disable=SC2016
    curl -fsSL "${MANIFEST_URL}" \
        jq -e --arg ARCH "${ARCH}" '.manifests[] | select(.platform.architecture == $ARCH)'
}

extra_usage_args() {
    echo '<installer image> <talos version>'
}

extra_plan_checks() {
    check_if_image_exists
}

extra_inputs_set() {
    TALOS_VERSION="${TALOS_VERSION:-"${SYSTEM_UPGRADE_PLAN_LATEST_VERSION}"}"


    INSTALLER_IMAGE="${1:-"${INSTALLER_IMAGE}"}"
    [[ -n "${INSTALLER_IMAGE}" ]] || usage
}

upgrade() {
    echo "Beginning upgrade..."
    talosctl -n 127.0.0.1 upgrade \
      "--image=${INSTALLER_IMAGE}:${TALOS_VERSION}" \
      --stage \
      --preserve=true \
      --wait=false
}

# shellcheck source=lib.sh
. "$(dirname "${0}")/lib.sh"
