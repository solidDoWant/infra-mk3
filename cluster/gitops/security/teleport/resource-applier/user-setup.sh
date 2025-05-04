#!/bin/bash
# cspell:words tctl

# The Teleport operator does not currently have a resource for bot users.
# Unfortunately this means that to run `tctl` or other Teleport cluster
# commands, the script must exec into a Teleport auth server pod to set
# one up.

set -euo pipefail

# shellcheck disable=SC2034
REQUIRED_ENV_VARS=(NAMESPACE AUTH_SERVER_DEPLOYMENT_NAME BOT_NAME ROLE_NAME TOKEN_NAME)

additional_setup() {
    # Install kubectl
    echo "Installing kubectl..."
    KUBECTL_VERSION="v1.32.3"
    curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${KERNEL}/${PRETTY_ARCH}/kubectl"
    chmod +x /usr/local/bin/kubectl
}

remote_tctl() {
    kubectl exec -n "${NAMESPACE}" deployment/"${AUTH_SERVER_DEPLOYMENT_NAME}" -c teleport -- \
        tctl "${@}"
}

run() {
    echo "Checking if bot '${BOT_NAME}' exists..."
    BOT_COUNT="$(remote_tctl get bots | yq ea '[.] | map(select(.metadata.name == env(BOT_NAME))) | length()')"
    if [[ "${BOT_COUNT}" != '0' ]]; then
        echo "Found existing bot with name '${BOT_NAME}'"
    else
        echo "Setting up new bot '${BOT_NAME}'..."
        remote_tctl bots add --roles "${ROLE_NAME}" --token "${TOKEN_NAME}" "${BOT_NAME}"
    fi

    echo "Setup complete!"
}

# shellcheck source=lib.sh
. "$(dirname "${0}")/lib.sh"
