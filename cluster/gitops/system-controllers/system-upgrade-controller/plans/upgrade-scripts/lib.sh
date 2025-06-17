#!/bin/bash

# Usage:
# 
# ```shell
# extra_plan_checks() { }
# extra_usage_args() { }
# extra_inputs_set() { }
# upgrade_command() { }
# 
# # shellcheck source=lib.sh
# . "$(dirname "${0}")/lib.sh"
# ```

set -euo pipefail

usage() {
    cat <<- EOF
	Usage: ${0} {plan|upgrade} <node name> <node ip> <talos version> $(extra_usage_args)
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

node_talosctl() {
    talosctl -n "${NODE_IP}" -e "${NODE_IP}" "$@"
}

# TODO create an image with these tools pre-installed
install_deps() {
    echo "Installing talosctl ${TALOS_VERSION} for ${ARCH}..."
    curl -fsSL -o /usr/local/bin/talosctl "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-${ARCH}"
    chmod +x /usr/local/bin/talosctl
}

# Not currently needed
# check_if_drained() {
#     echo 'Checking if node has been drained...'

#     DRAIN_OUTPUT="$(
#         kubectl drain "${NODE_NAME}" \
#             --delete-emptydir-data \
#             --ignore-daemonsets \
#             --dry-run=server
#     )"

#     if echo "${DRAIN_OUTPUT}" | grep -q "^node/${NODE_NAME} cordoned"; then
#         >&2 echo "Node has not yet been cordoned, failing"
#         exit 1
#     fi

#     if [[ "$(echo "${DRAIN_OUTPUT}" | wc -l)" != 2 ]]; then
#         >&2 cat <<- EOF
# 		Node has not yet been drained, failing
# 		Remaining pods:
# 		$(echo "${DRAIN_OUTPUT}" | awk 'NR>2 {print last} {last=$3}')
# 		EOF
#         exit 1
#     fi

#     echo 'Node has been drained'
# }

check_if_healthy() {
    echo 'Checking current node health...'

    node_talosctl health --server=false || FAILED='true'

    if [[ "${FAILED:-false}" != 'true' ]]; then
        echo 'Health check passed'
        return
    fi

    >&2 printf 'Health check failed, '

    if [[ "${IGNORE_UNHEALTH:-false}" == 'true' ]]; then
        >&2 echo 'continuing due to IGNORE_UNHEALTHY=true'
    else
        >&2 echo 'failing'
        exit 1
    fi
}

check_if_active_job_pods() {
    echo 'Checking if node contains pods with active-jobs label...'

    ACTIVE_JOB_PODS="$(kubectl get pods -A -l "active-jobs" --field-selector spec.nodeName="${NODE_NAME}" --no-headers)"
    if [ -n "${ACTIVE_JOB_PODS}" ]; then
        >&2 echo "Node contains pods with active jobs, failing"
        exit 1
    fi

    echo 'Checking if node active pods owned by a job...'

    ACTIVE_NODE_PODS="$(\
        kubectl get pods -A \
            --field-selector "spec.nodeName=${NODE_NAME},status.phase!=Failed,status.phase!=Succeeded" \
            -o json \
    )"
    ACTIVE_NODE_JOB_PODS="$(\
        echo "${ACTIVE_NODE_PODS}" | \
        jq -r --arg SELF_NAME "$(hostname)" '
            .items[] | 
            select(.metadata.ownerReferences[]?.kind == "Job") | 
            select(.metadata.namespace != "system-controllers" or .metadata.name != $SELF_NAME) | 
            .metadata.namespace + "/" + .metadata.name
        ' \
    )"

    if [ -n "${ACTIVE_NODE_JOB_PODS}" ]; then
        >&2 echo "Node contains active pods owned by jobs, failing"
        exit 1
    fi

    echo 'No active job pods found'
}

plan() {
    echo "Performing pre-upgrade checks..."

    set_arch
    install_deps
    check_if_healthy
    extra_plan_checks
    check_if_active_job_pods

    echo "All checks passed"
}

upgrade() {
    echo "Beginning upgrade..."

    set_arch
    install_deps
    upgrade_command

    echo "Upgrade complete!"
}

OPERATION="${1}"
[[ -n "${OPERATION}" ]] || usage

extra_inputs_set "${@:4}"

NODE_NAME="${2:-"${NODE_NAME}"}"
[[ -n "${NODE_NAME}" ]] || usage

NODE_IP="${3:-"${NODE_IP}"}"
[[ -n "${NODE_IP}" ]] || usage

TALOS_VERSION="${4:-"${TALOS_VERSION}"}"
[[ -n "${TALOS_VERSION}" ]] || usage


case "${OPERATION}" in
    prepare) plan ;;
    upgrade) upgrade ;;
    *) usage ;;
esac
