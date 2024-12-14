#!/bin/bash

# Usage:
# 
# ```shell
# REQUIRED_ENV_VARS=()  # Optional
# additional_setup() { }
# run() { }
# 
# # shellcheck source=lib.sh
# . "$(dirname "${0}")/lib.sh"
# ```

set -euo pipefail

REQUIRED_ENV_VARS+=()

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

    additional_setup

    echo "Setup complete"
}


check_env_vars
setup
run
