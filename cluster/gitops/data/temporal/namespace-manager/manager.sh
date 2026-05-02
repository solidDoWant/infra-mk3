#!/bin/sh
# shellcheck shell=ash
# cspell:words badouralix temporalio automount Iseconds
# Reconcile Temporal namespaces against k8s namespaces labeled with NAMESPACE_LABEL.
# - Adds the managed-by tag to the Temporal namespace `data` map on create so we
#   can distinguish operator-managed namespaces from manually-created ones (like
#   `temporal-system`) and avoid deleting them.
# - Filters managed namespaces by `state == Registered` so in-flight deletions
#   (which transition through `Deleted` while the system workflow runs) don't
#   get re-deleted on every tick.
#
# Runs under busybox /bin/sh (no bash). The badouralix/curl-jq base image ships
# curl + jq + busybox utils. The `temporal` CLI is mounted in via an OCI image
# volume from temporalio/admin-tools — referenced through $TEMPORAL.

set -eu
# busybox ash supports pipefail. Without it, a failing curl/temporal would be
# masked by a successful `sort` at the end of the pipeline.
set -o pipefail

: "${TEMPORAL_ADDRESS:?missing required env var}"
: "${NAMESPACE_LABEL:?missing required env var}"
: "${POLL_INTERVAL_SECONDS:?missing required env var}"
: "${MANAGED_BY_TAG:?missing required env var}"
: "${TEMPORAL:?missing required env var}"

# `temporal` CLI reads this env var implicitly.
export TEMPORAL_ADDRESS

# In-cluster API access. The kubelet projects these into every pod that has
# automountServiceAccountToken (default: true).
SA_DIR=/var/run/secrets/kubernetes.io/serviceaccount
K8S_API=https://kubernetes.default.svc

list_desired_namespaces() {
    # --fail-with-body so HTTP 4xx/5xx becomes a non-zero exit AND prints the
    # response body so the operator can debug.
    curl -sS --fail-with-body \
        --cacert "${SA_DIR}/ca.crt" \
        -H "Authorization: Bearer $(cat "${SA_DIR}/token")" \
        --get \
        --data-urlencode "labelSelector=${NAMESPACE_LABEL}=true" \
        "${K8S_API}/api/v1/namespaces" \
        | jq -r '.items[].metadata.name' \
        | sort -u
}

list_managed_namespaces() {
    "${TEMPORAL}" operator namespace list -o json \
        | jq -r --arg tag "${MANAGED_BY_TAG}" '
            .[]?
            | select(.namespaceInfo.data["managed-by"] == $tag)
            | select(.namespaceInfo.state == "Registered")
            | .namespaceInfo.name' \
        | sort -u
}

reconcile() {
    # If either list call fails, abort this tick. An empty `desired` from a
    # successful k8s API call is fine (means delete everything managed); an
    # empty `desired` from an *errored* call would also delete everything
    # managed, which we don't want.
    desired=$(list_desired_namespaces) || {
        echo "k8s namespace list failed; skipping reconcile" >&2
        return 1
    }
    managed=$(list_managed_namespaces) || {
        echo "temporal namespace list failed; skipping reconcile" >&2
        return 1
    }

    # POSIX sh has no <(...) process substitution; use temp files for `comm`.
    desired_file=$(mktemp)
    managed_file=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '${desired_file}' '${managed_file}'" EXIT
    printf '%s\n' "${desired}" > "${desired_file}"
    printf '%s\n' "${managed}" > "${managed_file}"
    to_create=$(comm -23 "${desired_file}" "${managed_file}")
    to_delete=$(comm -13 "${desired_file}" "${managed_file}")
    rm -f "${desired_file}" "${managed_file}"
    trap - EXIT

    printf '%s\n' "${to_create}" | while IFS= read -r ns; do
        [ -z "${ns}" ] && continue
        echo "+ creating temporal namespace: ${ns}"
        "${TEMPORAL}" operator namespace create \
            --namespace "${ns}" \
            --data "managed-by=${MANAGED_BY_TAG}" \
            || echo "  failed to create ${ns}" >&2
    done

    printf '%s\n' "${to_delete}" | while IFS= read -r ns; do
        [ -z "${ns}" ] && continue
        echo "- deleting temporal namespace: ${ns}"
        "${TEMPORAL}" operator namespace delete \
            --namespace "${ns}" \
            --yes \
            || echo "  failed to delete ${ns}" >&2
    done
}

while :; do
    echo "[$(date -u -Iseconds)] reconciling..."
    reconcile || true
    echo "[$(date -u -Iseconds)] sleeping ${POLL_INTERVAL_SECONDS}s"
    sleep "${POLL_INTERVAL_SECONDS}"
done
