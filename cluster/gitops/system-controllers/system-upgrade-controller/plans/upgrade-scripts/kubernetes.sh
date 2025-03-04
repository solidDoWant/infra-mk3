#!/bin/bash

upgrade_command() {
    node_talosctl upgrade-k8s --to "${KUBERNETES_VERSION}" "$@"
}

extra_usage_args() {
    echo '<kubernetes version>'
}

extra_plan_checks() {
    upgrade_command --dry-run
}

extra_inputs_set() {
    KUBERNETES_VERSION="${1:-"${KUBERNETES_VERSION}"}"
    [[ -n "${KUBERNETES_VERSION}" ]] || usage
}

# shellcheck source=lib.sh
. "$(dirname "${0}")/lib.sh"
