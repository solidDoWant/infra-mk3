#!/bin/bash

# Usage:
# 
# ```shell
# additional_setup() { }
# run() { }
# 
# # shellcheck source=lib.sh
# . "$(dirname "${0}")/lib.sh"
# ```

set -euo pipefail

REQUIRED_ENV_VARS=(TELEPORT_PROXY_ADDRESS NAMESPACE AUTH_SERVER_DEPLOYMENT_NAME BOT_NAME ROLE_NAME TOKEN_NAME TELEPORT_IDENTITY_FILE)

fatal() {
    >&2 echo "$@"
    exit 1
}

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

setup() {
    # Install deps
    echo "Installing dependencies..."
    # TODO move this to container image, just not worth the effort right now
    apt update
    apt install -y --no-install-recommends curl ca-certificates

    # Install yq
    echo "Installing yq..."
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')"
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)"
    curl -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/download/v4.44.6/yq_${KERNEL}_${PRETTY_ARCH}"
    chmod +x /usr/local/bin/yq

    # Install Teleport binaries
    echo "Installing teleport..."
    TELEPORT_VERSION="$(curl -fsSL "https://${TELEPORT_PROXY_ADDRESS}/v1/webapi/ping" | yq '.server_version')"
    TELEPORT_MAJOR_VERSION="$( echo "${TELEPORT_VERSION}" | cut -d. -f1)"
    # shellcheck source=/dev/null
    source /etc/os-release
    curl -fsSL https://apt.releases.teleport.dev/gpg \
        -o /usr/share/keyrings/teleport-archive-keyring.asc
    echo "deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.asc] \
        https://apt.releases.teleport.dev/${ID} ${VERSION_CODENAME} \
        stable/v${TELEPORT_MAJOR_VERSION}" > /etc/apt/sources.list.d/teleport.list
    apt update
    apt install -y --no-install-recommends "teleport-ent=${TELEPORT_VERSION}"

    additional_setup

    echo "Setup complete"
}


# check_env_vars
# setup
# run
