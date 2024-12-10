#!/bin/bash
# cspell: words Upserting inotify inotifywait nullglob tbot tctl

set -euo pipefail

REQUIRED_ENV_VARS=(RESOURCES_DIRECTORY TELEPORT_PROXY_ADDRESS NAMESPACE AUTH_SERVER_DEPLOYMENT_NAME BOT_NAME ROLE_NAME TOKEN_NAME)

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

    if [[ ! -d "${RESOURCES_DIRECTORY}" ]]; then
        fatal "Resources directory '${RESOURCES_DIRECTORY}' does not exist"
    fi
}

remote_tctl() {
    kubectl exec -n "${NAMESPACE}" deployment/"${AUTH_SERVER_DEPLOYMENT_NAME}" -c teleport -- \
        tctl "${@}"
}

# The Teleport operator does not currently have a resource for bot users.
# Unfortunately this means that to run `tctl` or other Teleport cluster
# commands, the script must exec into a Teleport auth server pod to set
# one up.
setup_bot() {
    echo "Authenticating with Teleport..."
    BOT_COUNT="$(remote_tctl get bots | yq ea '[.] | map(select(.metadata.name == env(BOT_NAME))) | length()')"
    if [[ "${BOT_COUNT}" == '0' ]]; then
        echo "Setting up new bot '${BOT_NAME}'..."
        remote_tctl bots add --roles "${ROLE_NAME}" --token "${TOKEN_NAME}" "${BOT_NAME}"
    else
        echo "Found existing bot with name '${BOT_NAME}', attempting to use it"
    fi

    # Run tbot in the background to renew certificates automatically
    tbot start \
        --data-dir=/var/lib/teleport/bot \
        --destination-dir=/opt/machine-id \
        --token="${TOKEN_NAME}" \
        --proxy-server="${TELEPORT_PROXY_ADDRESS}" \
        --join-method=kubernetes &
    
    export TELEPORT_IDENTITY_FILE='/opt/machine-id/identity'
    export TELEPORT_AUTH_SERVER="${TELEPORT_PROXY_ADDRESS}"

    # Wait for the identity file to exist
    echo "Waiting for startup to complete..."
    while [[ ! -f "${TELEPORT_IDENTITY_FILE}" ]]; do
        printf '.'
        sleep 1
    done

    echo "Successfully authenticated with ${TELEPORT_PROXY_ADDRESS}"
}

setup() {
    # Install deps
    echo "Installing dependencies..."
    # TODO move this to container image, just not worth the effort right now
    apt update
    apt install -y --no-install-recommends curl ca-certificates inotify-tools

    # Install yq
    echo "Installing yq..."
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')"
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)"
    curl -fsSL -o /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/download/v4.44.6/yq_${KERNEL}_${PRETTY_ARCH}"
    chmod +x /usr/local/bin/yq

    # Install kubectl
    echo "Installing kubectl..."
    KUBECTL_VERSION="v1.31.2"
    curl -fsSL -o /usr/local/bin/kubectl \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${KERNEL}/${PRETTY_ARCH}/kubectl"
    chmod +x /usr/local/bin/kubectl

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
    
    # Authenticate with Teleport
    setup_bot

    echo "Setup complete"
}

upsert_changes() {
    FILE_PATH="${1}"
    echo "Upserting resources from ${FILE_PATH}"
    tctl create -f "${FILE_PATH}" || true
}

delete_changes() {
    FILE_PATH="${1}"
    echo "Deleting resources from ${FILE_PATH}"

    while read -r resource_name; do
        echo "Deleting ${resource_name}"
        tctl rm "${resource_name}" || true
    done < <(yq -r ea '[.kind + "/" + .metadata.name] | join("\n")' "${FILE_PATH}")
}

apply_initial() {
    echo "Performing initial apply..."
    shopt -s nullglob
    for file in "${RESOURCES_DIRECTORY}"/*; do
        upsert_changes "${file}"
    done
}

watch_for_changes() {
    echo "Watching for changes..."
    inotifywait -m -e modify -e create -e delete --format "%w%f,%e" "${RESOURCES_DIRECTORY}" | while read -r notification; do
        FILE_PATH="$(echo "${notification}" | cut -d',' -f1)"
        IFS=',' read -r -a EVENTS <<< "$(echo "${notification}" | cut -d',' -f2-)"

        for event in "${EVENTS[@]}"; do
            echo "Detected ${event} on ${FILE_PATH}"

            case "${event}" in
                CREATE) ;&
                MODIFY) upsert_changes "${FILE_PATH}" ;;
                DELETE) delete_changes "${FILE_PATH}" ;;
                *) fatal "Unsupported event '${event}' (script bug)" ;;
            esac
        done
    done
}


check_env_vars
setup
apply_initial
watch_for_changes
