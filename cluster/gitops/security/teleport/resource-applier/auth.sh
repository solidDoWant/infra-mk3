#!/bin/bash
# cspell: words tbot tctl

set -euo pipefail

additional_setup() {
    # Install kubectl
    echo "Installing kubectl..."
    KUBECTL_VERSION="v1.31.2"
    curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${KERNEL}/${PRETTY_ARCH}/kubectl"
    chmod +x /usr/local/bin/kubectl
}

remote_tctl() {
    kubectl exec -n "${NAMESPACE}" deployment/"${AUTH_SERVER_DEPLOYMENT_NAME}" -c teleport -- \
        tctl "${@}"
}

run() {
    echo "Authenticating with Teleport..."

    # The Teleport operator does not currently have a resource for bot users.
    # Unfortunately this means that to run `tctl` or other Teleport cluster
    # commands, the script must exec into a Teleport auth server pod to set
    # one up.
    BOT_COUNT="$(remote_tctl get bots | yq ea '[.] | map(select(.metadata.name == env(BOT_NAME))) | length()')"
    if [[ "${BOT_COUNT}" == '0' ]]; then
        echo "Setting up new bot '${BOT_NAME}'..."
        remote_tctl bots add --roles "${ROLE_NAME}" --token "${TOKEN_NAME}" "${BOT_NAME}"
    else
        echo "Found existing bot with name '${BOT_NAME}', attempting to use it"
    fi

    # This will never return unless it errors
    tbot start \
        --data-dir=/var/lib/teleport/bot \
        "--destination-dir=$(dirname "${TELEPORT_IDENTITY_FILE}")" \
        --token="${TOKEN_NAME}" \
        --proxy-server="${TELEPORT_PROXY_ADDRESS}" \
        --join-method=kubernetes
}

# shellcheck source=lib.sh
. "$(dirname "${0}")/lib.sh"
