#!/bin/bash
# Promotes the Docker cache of each project's newest successful push build on
# its default branch to be the project's golden cache, which later builds clone
# (../../golden-clone-policy.yaml).
#
# Only those builds can promote: Pipelines-as-Code sets the event-type label
# and branch annotation on PipelineRuns itself, overwriting anything a
# repository's .tekton/ files declare, so PR builds and builds of other
# branches never qualify. Snapshot names derive from the PipelineRun, so
# promoting the same run twice (another replica, a resync) is a no-op.
set -euo pipefail

# Golden snapshots kept per project. The newest is cloned; the previous one
# stays until its replacement is ready.
readonly KEEP=2
# How long to wait for a finished run's pods to finish too (sidecars are
# stopped after the PipelineRun reports success).
readonly POD_WAIT_SECONDS=120

log() { echo "$(date -u +%FT%TZ) $*"; }

# The cache volume of a run's docker Task pod that finished last, once every
# such pod has finished (and so released its volume, making the snapshot
# consistent). Empty if the run has no docker Task pods. "Finished" means all
# containers terminated, not phase Succeeded: Tekton stops the dind sidecar
# once the steps are done, and its non-zero exit leaves the pod Failed even
# when the TaskRun succeeded.
run_cache_pvc() {
  local ns="$1" run="$2" waited=0 pods
  while :; do
    pods="$(kubectl -n "$ns" get pods -l tekton.dev/pipelineRun="$run" -o json | jq '
      [.items[]
        | . as $pod
        | .spec.volumes[]?
        | select(.ephemeral.volumeClaimTemplate.metadata.labels["ci.home.arpa/docker-cache"] == "true")
        | {pvc: ($pod.metadata.name + "-" + .name),
           done: (($pod.status.containerStatuses // []) | length > 0 and all(.state.terminated != null)),
           finished: ([$pod.status.containerStatuses[]?.state.terminated.finishedAt] | max)}]')"
    if [ "$(jq 'all(.done)' <<<"$pods")" = true ]; then
      jq -r 'sort_by(.finished) | last | .pvc // empty' <<<"$pods"
      return
    fi
    if [ "$waited" -ge "$POD_WAIT_SECONDS" ]; then
      log "${ns}: ${run}: docker pods still running after ${POD_WAIT_SECONDS}s, skipping"
      return
    fi
    sleep 5
    waited=$((waited + 5))
  done
}

promote_namespace() {
  local ns="$1" branch run snapshot pvc
  branch="$(kubectl get namespace "$ns" -o jsonpath='{.metadata.annotations.ci\.home\.arpa/default-branch}')"
  [ -n "$branch" ] || return 0

  # Newest successful push build on the default branch. The branch annotation
  # is the pushed ref (refs/heads/<branch>).
  run="$(kubectl -n "$ns" get pipelineruns -l pipelinesascode.tekton.dev/event-type=push -o json | jq -r --arg b "$branch" '
    [.items[]
      | select((.metadata.annotations["pipelinesascode.tekton.dev/branch"] // "" | ltrimstr("refs/heads/")) == $b)
      | select(any(.status.conditions[]?; .type == "Succeeded" and .status == "True"))]
    | sort_by(.status.completionTime) | last | .metadata.name // empty')"
  [ -n "$run" ] || return 0

  snapshot="docker-cache-${run}"
  kubectl -n "$ns" get volumesnapshot "$snapshot" >/dev/null 2>&1 && return 0

  pvc="$(run_cache_pvc "$ns" "$run")"
  [ -n "$pvc" ] || return 0
  kubectl -n "$ns" get pvc "$pvc" >/dev/null 2>&1 || return 0

  log "${ns}: promoting ${pvc} (PipelineRun ${run})"
  kubectl -n "$ns" create -f - <<YAML || return 0
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: ${snapshot}
  labels:
    ci.home.arpa/docker-cache-golden: "true"
  annotations:
    ci.home.arpa/source-pipelinerun: ${run}
spec:
  volumeSnapshotClassName: ssd-replicated-3x-block
  source:
    persistentVolumeClaimName: ${pvc}
YAML

  # Drop all but the newest KEEP ready golden snapshots.
  kubectl -n "$ns" get volumesnapshots -l ci.home.arpa/docker-cache-golden=true -o json \
    | jq -r --argjson keep "$KEEP" '
      [.items[] | select(.status.readyToUse == true)]
      | sort_by(.metadata.creationTimestamp) | reverse | .[$keep:][] | .metadata.name' \
    | while read -r old; do
        log "${ns}: deleting old golden snapshot ${old}"
        kubectl -n "$ns" delete volumesnapshot "$old" --wait=false
      done
}

promote_all() {
  local ns
  for ns in $(kubectl get namespaces -l ci.home.arpa/project=true -o jsonpath='{.items[*].metadata.name}'); do
    promote_namespace "$ns" || log "${ns}: promotion failed"
  done
}

# Event-driven: react to push PipelineRuns finishing successfully. Each pass
# starts with a full scan, which catches anything missed while restarting or
# reconnecting; the watch is restarted every 30 minutes, so that scan also runs
# as a periodic resync. The watch is bounded with `timeout` rather than
# kubectl's --request-timeout: any such override flag makes kubectl skip its
# in-cluster config and fall back to localhost:8080.
while :; do
  promote_all
  timeout 1800 kubectl get pipelineruns --all-namespaces \
    -l pipelinesascode.tekton.dev/event-type=push \
    --watch-only \
    -o jsonpath='{.metadata.namespace}{" "}{.status.conditions[?(@.type=="Succeeded")].status}{"\n"}' \
    | while read -r ns succeeded; do
        if [ "$succeeded" = True ]; then
          promote_namespace "$ns" || log "${ns}: promotion failed"
        fi
      done || true
  # Don't spin against the API if the watch keeps failing.
  sleep 10
done
