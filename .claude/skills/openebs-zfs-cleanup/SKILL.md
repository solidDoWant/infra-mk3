---
name: openebs-zfs-cleanup
description: Diagnose and clean up dead openebs zfs-localpv ZFSVolumes — stuck volumes that never delete, orphaned CRs with no PV, and node-agent "cannot destroy dataset" error loops. Use when the user mentions stuck/orphaned ZFSVolumes, openebs destroy errors, ZFS datasets that won't delete, "filesystem has dependent clones", or asks to reconcile ZFSVolume CRs against PVs.
---

# openebs zfs-localpv Volume Cleanup

openebs zfs-localpv leaves behind **two distinct kinds of dead `ZFSVolume`** that look alike and have **opposite fixes**. Misclassifying them is the failure mode this skill exists to prevent.

**Critical rule: Triage → classify every candidate → verify preconditions → trial on ONE → verify → batch. Never delete or destroy in bulk before a single-item trial succeeds.**

> ## ⛔ Never run `zfs destroy -R`
>
> ZFS's own error message recommends it. On 2026-07-19 it would have destroyed **14 live production databases**. A clone-blocked dataset is not garbage — it shares blocks with running Postgres. Use `zfs promote` (Mode A below). There is no situation in this cluster where `-R` is the right answer.

## Environment

| | |
|---|---|
| Namespace | `storage` |
| Pool root | `local-storage/openebs` |
| Node pods | `openebs-zfs-localpv-node-*`, container `openebs-zfs-plugin` |
| Nodes | `talos-k8s-mixed-01/02/03` |

`ZFSVolume` CRs are **namespaced to `storage`** — `kubectl get zfsvolumes -n openebs` silently returns nothing and will mislead you.

## Step 1: Triage — classify before touching anything

```bash
kubectl get zfsvolumes -n storage -o json | jq -r '.items[] |
  [.metadata.name, .spec.ownerNodeID, .status.state // "-",
   (.metadata.deletionTimestamp // "-"), (.spec.snapname // "-"),
   (.metadata.finalizers // [] | join(","))] | @tsv'
```

Classify each:

| Signal | Mode | Fix |
|---|---|---|
| `deletionTimestamp` set, won't go away, node agent logs destroy errors | **A — clone-blocked** | `zfs promote` (Step 3) |
| No PV, **no** `deletionTimestamp`, silent | **B — orphaned** ([#507](https://github.com/openebs/zfs-localpv/issues/507)) | delete the CR (Step 4) |
| `state=Failed`, no finalizer, no dataset | **B (debris)** | delete the CR, instant |

**Always re-derive the list from live state.** Counts from an earlier session or a prior report go stale — a previous cleanup may have already resolved some.

## Step 2: Preconditions (all modes)

```bash
# Per node: snapshots, and any dataset with an origin (= a clone)
for p in $(kubectl get pods -n storage --no-headers \
    -o custom-columns=N:.metadata.name,NODE:.spec.nodeName \
    | grep openebs-zfs-localpv-node | awk '{print $1":"$2}'); do
  pod=${p%%:*}; node=${p##*:}
  echo "--- $node"
  kubectl exec -n storage "$pod" -c openebs-zfs-plugin -- \
    zfs list -H -o name,used,origin,mounted -t filesystem,volume -r local-storage/openebs
done

kubectl get zfssnapshots -A -o json | jq '.items | length'   # note: bare `| wc -l` counts "No resources found"

# Baseline DB health — diff against this at the end
kubectl get cluster -A -o json | jq -r '.items[] |
  [.metadata.namespace+"/"+.metadata.name, .status.readyInstances, .status.instances] | @tsv' \
  | sort > db-before.txt
```

Interpretation:
- `origin != -` → that dataset **is a clone**. Its origin cannot be destroyed until promoted.
- `mounted=no` on a leaf PVC dataset → strong orphan signal. Cross-check that the set of unmounted datasets matches the orphan set exactly; if an orphan candidate is **mounted**, stop — something is using it.

## Step 3: Mode A — clone-blocked (`zfs promote`)

Promote the **clone**, not the origin. This inverts the relationship so the old origin becomes an ordinary snapshot of the clone and is no longer a dependency.

```bash
kubectl exec -n storage "$POD" -c openebs-zfs-plugin -- zfs promote "<clone-dataset>"
```

Then **wait** — do not force anything. openebs's own ~30s resync retries the destroy, succeeds, and clears the finalizer itself. Confirm the destroy-error rate on the node agent drops to zero.

Expect leftover untracked snapshots afterward: post-promote the snapshots migrate onto the live volumes, and openebs's destroy fails open at the old path, removing finalizers without destroying them. Clean up only after confirming **0 clones and 0 ZFSSnapshot CRs**, and read snapshot names from live `zfs list` output — never hand-type them.

## Step 4: Mode B — orphaned CRs

Cross-reference in **both** directions:

```bash
kubectl get zfsvolumes -n storage -o json | jq -r '.items[].metadata.name' | sort > zv.txt
kubectl get pv -o json | jq -r '.items[] |
  select(.spec.csi.driver? == "zfs.csi.openebs.io") | .metadata.name' | sort > pv.txt

comm -23 zv.txt pv.txt   # CRs with no PV  → the orphans
comm -13 zv.txt pv.txt   # PVs with no CR  → must be EMPTY (would mean over-deletion)
```

Before deleting, confirm nothing references them:

```bash
kubectl get pvc,volumesnapshot,volumesnapshotcontent -A -o json | jq -r --arg v "$V" \
  '[.items[] | select((.spec.volumeName? == $v)
     or (.status.snapshotHandle? // "" | contains($v))
     or (.spec.source.volumeHandle? // "" | contains($v)))] | length'
```

Then delete **ordered by ascending risk**: no-finalizer/no-dataset debris first, then a single-item trial on the *smallest* dataset-backed CR, verifying both that the CR is gone and the dataset was actually destroyed, before batching the rest.

```bash
kubectl delete zfsvolume -n storage "$V" --timeout=90s
kubectl exec -n storage "$POD" -c openebs-zfs-plugin -- \
  zfs list -H -o name "local-storage/openebs/<parent>/$V"   # expect "dataset does not exist"
```

**Watch for duplicated finalizers.** One CR carried `zfs.openebs.io/finalizer` twice; if the driver strips only one occurrence the CR wedges. Sequence any such CR last and watch it individually.

## Step 5: Verification

```bash
# Parity — the real exit test, both directions
# Both counts equal, and both comm outputs empty.

# Unmounted datasets remaining → expect 0 per node

# DB health unchanged
kubectl get cluster -A -o json | jq -r '.items[] |
  [.metadata.namespace+"/"+.metadata.name, .status.readyInstances, .status.instances] | @tsv' \
  | sort > db-after.txt
diff db-before.txt db-after.txt
```

**Checking for pod restarts: use container start times, not `restartCount`.** `restartCount` is a lifetime total and will show non-zero values that have nothing to do with your work.

```bash
kubectl get pods -A -l cnpg.io/podRole=instance -o json | jq -r '
  .items[] | . as $p | ($p.status.containerStatuses[]? | select(.name=="postgres")) as $c |
  [($c.state.running.startedAt // "-"), $p.metadata.namespace+"/"+$p.metadata.name] | @tsv' \
  | sort -r | head
```

Compare the newest start time against when the operation began.

## Context worth stating in the report

Both modes **recur structurally** — this is janitorial, not a fix:

- **Mode A** rebuilds on *every* snapshot-restore. openebs clones unconditionally when `spec.snapname` is set, with no detached-restore option; `grep -rni promote` across v2.9.0 returns zero matches, v2.10.1 unchanged. #236/#123 closed prematurely, clone-side PRs #606/#350 unmerged. **Don't file upstream** — the user has explicitly declined this.
- **Mode B** accrues at roughly 1 per 2–3 months.

The durable escape from Mode A is dropping snapshot-based CNPG bootstrap on this driver; democratic-csi's `detachedSnapshots` does a full send/recv and produces no `origin`. The durable detection for Mode B is a vmalert rule on the CR-vs-PV count, which needs custom kube-state-metrics resource-state config.
