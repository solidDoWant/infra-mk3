#!/bin/bash
# cspell:words Upserting inotify inotifywait nullglob tctl

set -euo pipefail

# shellcheck disable=SC2034
REQUIRED_ENV_VARS=(TELEPORT_PROXY_ADDRESS TELEPORT_IDENTITY_FILE RESOURCES_DIRECTORY)

additional_setup() {
    # Install inotifywait
    echo "Installing inotify-tools..."
    apt install -y --no-install-recommends inotify-tools

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

    echo "Waiting for identity file to become available..."
    while [[ ! -f "${TELEPORT_IDENTITY_FILE}" ]]; do
        printf '.'
        sleep 1
    done

    export TELEPORT_AUTH_SERVER="${TELEPORT_PROXY_ADDRESS}"
    echo "Successfully authenticated with ${TELEPORT_PROXY_ADDRESS}"
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

run() {
    apply_initial
    watch_for_changes
}

# shellcheck source=lib.sh
. "$(dirname "${0}")/lib.sh"

