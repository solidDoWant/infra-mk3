#!/bin/bash
# Promotes the Docker cache of each project's newest successful push build on
# its default branch to be the project's golden cache, which later builds clone
# (../../golden-clone-policy.yaml).
#
# Only those builds can promote: Pipelines-as-Code sets the event-type label
# and branch annotation on PipelineRuns itself, overwriting anything a
# repository's .tekton/ files declare, so PR builds and builds of other
# branches never qualify.
#
# A golden cache is a standalone copy in one of the single-copy ci-cache-*
# pools, not a clone of the build's volume: Ceph CSI snapshots and restores
# are copy-on-write clones, so chaining them would make every build depend on
# every pool its cache's history passed through. For a run, in its project
# namespace:
#   1. docker-cache-seed-<run>: a snapshot of the build's cache volume, which
#      outlives the build pod (deleting the pod deletes the volume).
#   2. docker-cache-src-<run>: the seed restored in its own pool (a cheap
#      copy-on-write clone), as something a pod can read.
#   3. docker-cache-<run>: a blank volume in the least-loaded healthy pool.
#   4. docker-cache-copy-<run>: a pod copying 2 into 3, skipping zeroed blocks.
#   5. docker-cache-<run> (VolumeSnapshot): the golden snapshot of 3.
# Then everything but the golden snapshot is deleted. Names derive from the
# PipelineRun, so every step can resume after a restart, and a run with a
# golden snapshot is done. There's one replica, so nothing else works on the
# same run.
set -euo pipefail

# Golden snapshots kept per project. The newest usable one is cloned; the
# previous one stays as a fallback for when the newest one's pool is down.
readonly KEEP=2
# How long to wait for a finished run's pods to finish too (native sidecars
# are stopped after the steps).
readonly POD_WAIT_SECONDS=120
# Timeouts for a snapshot or volume to become ready, and for the copy.
readonly READY_TIMEOUT=10m
readonly COPY_TIMEOUT_SECONDS=3600
# GNU dd, for conv=sparse (busybox's dd has no sparse writes)
readonly COPY_IMAGE="public.ecr.aws/docker/library/debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2"
# The cache pools and their nodes. Keep in step with the pools (rook-ceph
# cluster hr.yaml) and ../../golden-clone-policy.yaml.
readonly -A POOL_NODES=(
  ["ci-cache-mixed-01"]=talos-k8s-mixed-01
  ["ci-cache-mixed-02"]=talos-k8s-mixed-02
  ["ci-cache-mixed-03"]=talos-k8s-mixed-03
)

log() { echo "$(date -u +%FT%TZ) $*"; }

# The cache volume of a run's docker Task pod that finished last, once every
# such pod has finished (and so released its volume, making the snapshot
# consistent). Empty if the run has no docker Task pods. "Finished" means all
# containers terminated, including the dind sidecar, which is a native
# sidecar and so reports under initContainerStatuses. Not phase Succeeded:
# the sidecar's exit status on shutdown isn't the build's.
run_cache_pvc() {
  local ns="$1" run="$2" waited=0 pods
  while :; do
    pods="$(kubectl -n "$ns" get pods -l tekton.dev/pipelineRun="$run" -o json | jq '
      [.items[]
        | . as $pod
        | .spec.volumes[]?
        | select(.ephemeral.volumeClaimTemplate.metadata.labels["ci.home.arpa/docker-cache"] == "true")
        | {pvc: ($pod.metadata.name + "-" + .name),
           statuses: (($pod.status.containerStatuses // []) + ($pod.status.initContainerStatuses // []))}
        | {pvc, done: (.statuses | length > 0 and all(.state.terminated != null)),
           finished: ([.statuses[].state.terminated.finishedAt] | max)}]')"
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

# Cache pools whose OSD is up and whose node isn't cordoned, least loaded
# (fewest docker cache volumes) first, ties in random order. The same choice
# the Kyverno policy makes for build volumes.
healthy_pools() {
  local up schedulable load pool node
  up="$(kubectl -n storage get deployments -l app=rook-ceph-osd -o json \
    | jq -c '[.items[] | select((.status.availableReplicas // 0) > 0) | .metadata.labels["topology-location-host"]]')"
  schedulable="$(kubectl get nodes -o json | jq -c '[.items[] | select(.spec.unschedulable != true) | .metadata.name]')"
  load="$(kubectl get pvc -A -l ci.home.arpa/docker-cache=true -o json | jq -c '[.items[].spec.storageClassName]')"
  for pool in "${!POOL_NODES[@]}"; do
    node="${POOL_NODES[$pool]}"
    jq -e --arg n "$node" 'index($n) != null' <<<"$up" >/dev/null || continue
    jq -e --arg n "$node" 'index($n) != null' <<<"$schedulable" >/dev/null || continue
    echo "$(jq --arg p "$pool" '[.[] | select(. == $p)] | length' <<<"$load") $RANDOM $pool"
  done | sort -n -k1,1 -k2,2 | awk '{print $3}'
}

# Creates the object in stdin unless one of that kind and name exists.
ensure() {
  local ns="$1" kind="$2" name="$3"
  kubectl -n "$ns" get "$kind" "$name" >/dev/null 2>&1 && return 0
  kubectl -n "$ns" create -f - >/dev/null
}

wait_snapshot() {
  kubectl -n "$1" wait "volumesnapshot/$2" --for=jsonpath='{.status.readyToUse}'=true --timeout="$READY_TIMEOUT" >/dev/null
}

wait_bound() {
  kubectl -n "$1" wait "pvc/$2" --for=jsonpath='{.status.phase}'=Bound --timeout="$READY_TIMEOUT" >/dev/null
}

# Waits for the copy pod to succeed. Fails if it fails or runs too long.
wait_copy() {
  local ns="$1" pod="$2" waited=0 phase
  while [ "$waited" -lt "$COPY_TIMEOUT_SECONDS" ]; do
    phase="$(kubectl -n "$ns" get pod "$pod" -o jsonpath='{.status.phase}')"
    case "$phase" in
      Succeeded) return 0 ;;
      Failed)
        log "${ns}: ${pod} failed: $(kubectl -n "$ns" logs "$pod" --tail=5 2>&1 | tr '\n' ' ')"
        return 1
        ;;
    esac
    sleep 10
    waited=$((waited + 10))
  done
  log "${ns}: ${pod} didn't finish in ${COPY_TIMEOUT_SECONDS}s"
  return 1
}

volume() { # name storage-class size [snapshot]
  cat <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $1
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Block
  storageClassName: $2
  resources:
    requests:
      storage: $3
YAML
  if [ -n "${4:-}" ]; then
    cat <<YAML
  dataSource:
    apiGroup: snapshot.storage.k8s.io
    kind: VolumeSnapshot
    name: $4
YAML
  fi
}

snapshot() { # name pvc [extra label lines]
  cat <<YAML
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $1
  labels:
    ci.home.arpa/docker-cache-promotion: "true"
${3:-}
spec:
  volumeSnapshotClassName: ssd-replicated-3x-block
  source:
    persistentVolumeClaimName: $2
YAML
}

copy_pod() { # name source-pvc destination-pvc
  cat <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $1
  labels:
    ci.home.arpa/docker-cache-promotion: "true"
spec:
  # Project namespaces only admit kata pods (ci-build-pods).
  runtimeClassName: kata
  restartPolicy: Never
  automountServiceAccountToken: false
  enableServiceLinks: false
  containers:
    - name: copy
      image: ${COPY_IMAGE}
      # Direct I/O keeps the copy out of the page cache, and so inside the
      # memory limit. The blank destination reads as zeros, so zeroed
      # blocks are skipped rather than written.
      command:
        - dd
        - if=/dev/source
        - of=/dev/destination
        - bs=4M
        - iflag=direct
        - oflag=direct
        - conv=sparse,fsync
        - status=none
      volumeDevices:
        - name: source
          devicePath: /dev/source
        - name: destination
          devicePath: /dev/destination
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop:
            - ALL
      # The pod's memory also covers the kata VM's hypervisor on the host,
      # whose buffered writes to the volume count against it: at 128Mi the
      # host OOM-killed the hypervisor mid-copy.
      resources:
        requests:
          cpu: 100m
          memory: 1Gi
        limits:
          memory: 1Gi
  volumes:
    - name: source
      persistentVolumeClaim:
        claimName: $2
        readOnly: true
    - name: destination
      persistentVolumeClaim:
        claimName: $3
YAML
}

# Deletes a run's intermediate objects, keeping its golden snapshot.
cleanup_run() {
  local ns="$1" run="$2"
  kubectl -n "$ns" delete pod "docker-cache-copy-${run}" --ignore-not-found --wait=false >/dev/null
  kubectl -n "$ns" delete pvc "docker-cache-src-${run}" "docker-cache-${run}" --ignore-not-found --wait=false >/dev/null
  kubectl -n "$ns" delete volumesnapshot "docker-cache-seed-${run}" --ignore-not-found --wait=false >/dev/null
}

# Copies a run's cache volume into a golden snapshot. Returns non-zero on any
# failure, leaving cleanup to the caller.
copy_to_golden() {
  local ns="$1" run="$2" pvc="$3" pool="$4"
  local seed="docker-cache-seed-${run}" src="docker-cache-src-${run}" dst="docker-cache-${run}"
  local copy="docker-cache-copy-${run}" size src_class

  if ! kubectl -n "$ns" get volumesnapshot "$seed" >/dev/null 2>&1; then
    src_class="$(kubectl -n "$ns" get pvc "$pvc" -o jsonpath='{.spec.storageClassName}')" || return 1
    snapshot "$seed" "$pvc" | ensure "$ns" volumesnapshot "$seed" || return 1
    # The build's volume (and so its class) goes with the build pod; a
    # resumed run reads it from here.
    kubectl -n "$ns" annotate volumesnapshot "$seed" "ci.home.arpa/source-storage-class=${src_class}" >/dev/null || return 1
  fi
  wait_snapshot "$ns" "$seed" || return 1
  size="$(kubectl -n "$ns" get volumesnapshot "$seed" -o jsonpath='{.status.restoreSize}')" || return 1
  # The seed's pool, so the restore is a copy-on-write clone.
  src_class="$(kubectl -n "$ns" get volumesnapshot "$seed" -o jsonpath='{.metadata.annotations.ci\.home\.arpa/source-storage-class}')" || return 1
  [ -n "$src_class" ] || return 1

  volume "$src" "$src_class" "$size" "$seed" | ensure "$ns" pvc "$src" || return 1
  volume "$dst" "$pool" "$size" | ensure "$ns" pvc "$dst" || return 1
  wait_bound "$ns" "$src" || return 1
  wait_bound "$ns" "$dst" || return 1

  copy_pod "$copy" "$src" "$dst" | ensure "$ns" pod "$copy" || return 1
  wait_copy "$ns" "$copy" || return 1

  # The pool of the volume actually copied into, which a resumed run may
  # have created in a different pool from the one picked this time.
  pool="$(kubectl -n "$ns" get pvc "$dst" -o jsonpath='{.spec.storageClassName}')" || return 1
  snapshot "$dst" "$dst" "    ci.home.arpa/docker-cache-golden: \"true\"
    ci.home.arpa/docker-cache-pool: ${pool}" | ensure "$ns" volumesnapshot "$dst" || return 1
  kubectl -n "$ns" annotate volumesnapshot "$dst" --overwrite "ci.home.arpa/source-pipelinerun=${run}" >/dev/null || return 1
  wait_snapshot "$ns" "$dst" || return 1
  log "${ns}: golden cache ${dst} ready in ${pool}"
}

promote_namespace() {
  local ns="$1" branch run golden pvc pool
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

  golden="docker-cache-${run}"
  if [ "$(kubectl -n "$ns" get volumesnapshot "$golden" -o jsonpath='{.status.readyToUse}' 2>/dev/null)" = true ]; then
    # Done; also clears what an interrupted cleanup left.
    cleanup_run "$ns" "$run"
    return 0
  fi

  # A resumed run keeps its seed snapshot, so it no longer needs the build's
  # volume.
  if ! kubectl -n "$ns" get volumesnapshot "docker-cache-seed-${run}" >/dev/null 2>&1; then
    pvc="$(run_cache_pvc "$ns" "$run")"
    [ -n "$pvc" ] || return 0
    kubectl -n "$ns" get pvc "$pvc" >/dev/null 2>&1 || return 0
  else
    pvc="$(kubectl -n "$ns" get volumesnapshot "docker-cache-seed-${run}" -o jsonpath='{.spec.source.persistentVolumeClaimName}')"
  fi

  pool="$(healthy_pools | head -n 1)"
  if [ -z "$pool" ]; then
    log "${ns}: ${run}: no healthy cache pool, not promoting"
    return 0
  fi

  log "${ns}: promoting ${pvc} (PipelineRun ${run}) into ${pool}"
  if ! copy_to_golden "$ns" "$run" "$pvc" "$pool"; then
    log "${ns}: ${run}: promotion failed, cleaning up"
    cleanup_run "$ns" "$run"
    kubectl -n "$ns" delete volumesnapshot "$golden" --ignore-not-found --wait=false >/dev/null
    return 1
  fi
  cleanup_run "$ns" "$run"

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
