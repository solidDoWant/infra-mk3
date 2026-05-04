#!/bin/sh
# shellcheck shell=ash
# cspell:words badouralix temporalio automount Iseconds ltrimstr
# Reconcile Temporal namespaces against k8s namespaces labeled with NAMESPACE_LABEL.
# - Adds the managed-by tag to the Temporal namespace `data` map on create so we
#   can distinguish operator-managed namespaces from manually-created ones (like
#   `temporal-system`) and avoid deleting them.
# - Filters managed namespaces by `state == Registered` so in-flight deletions
#   (which transition through `Deleted` while the system workflow runs) don't
#   get re-deleted on every tick.
# - Adds custom search attributes to a Temporal namespace from k8s annotations
#   prefixed with SEARCH_ATTRIBUTE_ANNOTATION_PREFIX. Each
#   `<prefix><Name>: <Type>` annotation becomes a `search-attribute create`
#   call. Additive only: removing the annotation does not drop the attribute,
#   and Temporal rejects type changes (those surface as "already exists" and
#   are silently ignored — the operator must drop and recreate manually).
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
: "${SEARCH_ATTRIBUTE_ANNOTATION_PREFIX:?missing required env var}"

# `temporal` CLI reads this env var implicitly.
export TEMPORAL_ADDRESS

# In-cluster API access. The kubelet projects these into every pod that has
# automountServiceAccountToken (default: true).
SA_DIR=/var/run/secrets/kubernetes.io/serviceaccount
K8S_API=https://kubernetes.default.svc

# Holds the raw k8s namespace API response for the current reconcile tick.
# Cached once per tick so derived views (names, per-namespace annotations) all
# read from the same snapshot without repeating the API call.
DESIRED_NS_RAW=""

fetch_desired_namespaces() {
    # --fail-with-body so HTTP 4xx/5xx becomes a non-zero exit AND prints the
    # response body so the operator can debug.
    DESIRED_NS_RAW=$(curl -sS --fail-with-body \
        --cacert "${SA_DIR}/ca.crt" \
        -H "Authorization: Bearer $(cat "${SA_DIR}/token")" \
        --get \
        --data-urlencode "labelSelector=${NAMESPACE_LABEL}=true" \
        "${K8S_API}/api/v1/namespaces")
}

list_desired_namespaces() {
    echo "${DESIRED_NS_RAW}" | jq -r '.items[].metadata.name' | sort -u
}

# For one k8s namespace, emit `Name=Type` lines — one per search-attribute
# annotation. Empty if the namespace has no matching annotations. Search
# attribute names follow Temporal naming rules (alphanumerics, no `=`), so an
# `=` separator is unambiguous.
list_desired_search_attrs() {
    ns="$1"
    echo "${DESIRED_NS_RAW}" \
        | jq -r --arg ns "${ns}" --arg prefix "${SEARCH_ATTRIBUTE_ANNOTATION_PREFIX}" '
            .items[]
            | select(.metadata.name == $ns)
            | (.metadata.annotations // {})
            | to_entries[]
            | select(.key | startswith($prefix))
            | "\(.key | ltrimstr($prefix))=\(.value)"
        '
}

# Normalize the temporal CLI's namespace-list output to a flat stream of
# namespace records. The CLI may emit a JSON array, JSON-Lines, or a wrapper
# object with a `namespaces` field depending on version, and the inner record
# may or may not be wrapped in `namespaceInfo`. `--slurp` collects every
# top-level value into one array; the unwrap step then peels back nesting so
# downstream filters always see a uniform `{name, state, data}` object.
NAMESPACE_FILTER='
    (if length == 1 and (.[0] | type) == "array" then .[0]
     elif length == 1 and (.[0] | type) == "object" and (.[0] | has("namespaces")) then .[0].namespaces
     else . end)
    | .[]?
    | (if has("namespaceInfo") then .namespaceInfo else . end)
    | select((.state | tostring) == "Registered"
          or (.state | tostring) == "NAMESPACE_STATE_REGISTERED")
'

# All Registered namespaces in Temporal, regardless of who owns them. Used
# to decide what to *create*: only namespaces missing from Temporal entirely
# get a create call. Manually-created or pre-existing namespaces (without the
# managed-by tag) are left alone instead of being re-attempted every cycle.
list_existing_namespaces() {
    echo "${TEMPORAL_NS_RAW}" \
        | jq -rs "${NAMESPACE_FILTER} | .name" \
        | sort -u
}

# Subset of Registered namespaces tagged as managed-by this controller. Used
# to decide what to *delete*: only namespaces this controller created can be
# pruned when the corresponding k8s namespace goes away.
list_managed_namespaces() {
    echo "${TEMPORAL_NS_RAW}" \
        | jq -rs --arg tag "${MANAGED_BY_TAG}" "
            ${NAMESPACE_FILTER}
            | select(.data[\"managed-by\"]? == \$tag)
            | .name" \
        | sort -u
}

# Idempotently ensure each annotated search attribute exists in the Temporal
# namespace. Try-and-absorb mirrors the namespace create path: "already exists"
# is the steady state on every tick after the first. Any other failure logs
# and continues — a freshly-created namespace that hasn't propagated yet will
# return "namespace not found" and be retried next tick.
reconcile_search_attributes() {
    ns="$1"
    sas=$(list_desired_search_attrs "${ns}")
    [ -z "${sas}" ] && return 0

    printf '%s\n' "${sas}" | while IFS='=' read -r sa_name sa_type; do
        [ -z "${sa_name}" ] && continue
        if create_output=$("${TEMPORAL}" operator search-attribute create \
            --namespace "${ns}" \
            --name "${sa_name}" \
            --type "${sa_type}" \
            --yes 2>&1); then
            echo "+ adding search attribute ${ns}/${sa_name} (${sa_type})"
        elif printf '%s' "${create_output}" | grep -qi 'already exists'; then
            :
        else
            printf '%s\n' "${create_output}" >&2
            echo "  failed to create search attribute ${ns}/${sa_name} (${sa_type})" >&2
        fi
    done
}

reconcile() {
    # If either list call fails, abort this tick. An empty `desired` from a
    # successful k8s API call is fine (means delete everything managed); an
    # empty `desired` from an *errored* call would also delete everything
    # managed, which we don't want.
    fetch_desired_namespaces || {
        echo "k8s namespace list failed; skipping reconcile" >&2
        return 1
    }
    desired=$(list_desired_namespaces)
    TEMPORAL_NS_RAW=$("${TEMPORAL}" operator namespace list -o json) || {
        echo "temporal namespace list failed; skipping reconcile" >&2
        return 1
    }
    existing=$(list_existing_namespaces)
    managed=$(list_managed_namespaces)

    # POSIX sh has no <(...) process substitution; use temp files for `comm`.
    desired_file=$(mktemp)
    existing_file=$(mktemp)
    managed_file=$(mktemp)
    # shellcheck disable=SC2064
    trap "rm -f '${desired_file}' '${existing_file}' '${managed_file}'" EXIT
    printf '%s\n' "${desired}" > "${desired_file}"
    printf '%s\n' "${existing}" > "${existing_file}"
    printf '%s\n' "${managed}" > "${managed_file}"
    # Create: in desired, not in temporal at all (skip pre-existing untagged
    # namespaces — the operator can adopt them by tagging manually if wanted).
    to_create=$(comm -23 "${desired_file}" "${existing_file}")
    # Delete: tagged as managed by us, but no longer desired.
    to_delete=$(comm -23 "${managed_file}" "${desired_file}")
    rm -f "${desired_file}" "${existing_file}" "${managed_file}"
    trap - EXIT

    printf '%s\n' "${to_create}" | while IFS= read -r ns; do
        [ -z "${ns}" ] && continue
        echo "+ creating temporal namespace: ${ns}"
        # 2160h = 90d. Temporal's --retention parses via Go time.ParseDuration,
        # which doesn't accept the `d` suffix.
        #
        # Capture combined output so we can quietly absorb "already exists"
        # without spamming the log on every tick. That can happen if the list
        # parsing missed a namespace (e.g. unexpected output shape) or if the
        # namespace was created out of band between the list and create.
        if create_output=$("${TEMPORAL}" operator namespace create \
            --namespace "${ns}" \
            --data "managed-by=${MANAGED_BY_TAG}" \
            --retention 2160h \
            --history-archival-state enabled \
            --visibility-archival-state enabled 2>&1); then
            :
        elif printf '%s' "${create_output}" | grep -q 'already exists'; then
            echo "  ${ns} already exists in temporal — skipping"
        else
            printf '%s\n' "${create_output}" >&2
            echo "  failed to create ${ns}" >&2
        fi
    done

    # Sync search attributes for every desired k8s namespace. Restricting to
    # `desired` (not `managed`) means we'll also add SAs to namespaces that
    # were pre-existing but have since been labeled — search attributes are
    # additive, so this can't damage a manually-managed namespace.
    printf '%s\n' "${desired}" | while IFS= read -r ns; do
        [ -z "${ns}" ] && continue
        reconcile_search_attributes "${ns}"
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
