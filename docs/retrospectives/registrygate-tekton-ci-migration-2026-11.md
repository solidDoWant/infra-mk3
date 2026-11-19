# Retrospective: moving registrygate's CI from GitHub Actions to Tekton (2026-11-16 to 2026-11-19)

Raw notes, not a guide. These are meant to be cut down later into (a) a migration playbook for other projects and (b) changes to the `agent-project` skill. Everything that happened is written down, including mistakes and dead ends. Numbers come from measurements unless marked as estimates.

Actors:
- **Owner:** the human.
- **Operator:** the interactive Claude Code session in the infra-mk3 devcontainer, which has cluster access.
- **PM:** the headless scheduler and planner in the `ghcr-proxy-vm` Coder VM, plus its worker, reviewer, bug-hunter and security-auditor subagents.
- **registrygate:** the product repo, `solidDoWant/registrygate`.

## 1. Goal and outcome

**The question being tested:** can CI runtime for one of the owner's projects be cut a lot by moving from GitHub-hosted runners to self-hosted Tekton in the homelab, with the agent-project setup doing the work?

**The outcome:** yes, roughly halved, but most of the gain came from changing how the tests run, not from the hardware.

| Measure | GitHub Actions | Tekton at the Phase 4 cutover | After CI-speed rounds 1 and 2 | Now (after the kind image cache) |
|---|---|---|---|---|
| PR wall clock p50, check suite created to last check done (`measure-ci.py`) | **9.5–9.6 min** (n=25–32) | **9.1 min** (n=10) | not re-measured this way | ~5.2 min for the first cache-seeding PR run (#238) |
| The `ci` TaskRun (all stages), controlled back-to-back runs | n/a | 349s (master `17a1e03`, 3 runs) | 319s (master `afdf11a`, 3 runs) | **270–277s** (master `385bfa9`, 3 runs) |
| e2e stage / job | 9.2–9.3 min (the job, with ~2–2.7 min of Nix setup) | 8.4 min p50 | 194–219s | **169–182s** |
| e2e-walkthrough stage | inside the e2e job | inside e2e | 257–271s | **219–226s** |
| unit / integration / lint / generate | 3.3 / 3.5 / 2.5 / 2.2 min | 1.1 / 1.3 / 0.3 / 0.1 min | ~1.1 / 1.3 min | same |

- The whole `ci` TaskRun is now about 4.5 min against GHA's 9.5 min p50: about 48%. The PaC wall clock adds pod start (~9s), the `test-guard` and `report` pods and PaC's own reporting on top, roughly 30–40s more.
- The owner's estimate was "a little under half, maybe 40%". The defensible numbers are 48% (TaskRun) to ~55% (PaC wall clock). Round 3 (#239–#243) was still running when this was written and should cut further; its estimate is a walkthrough of ~155s and a whole run of ~3.5 min.
- **Phase 4's cutover alone barely beat GHA (9.1 vs 9.5).** It removed every job's Nix setup and ran all stages at once in one VM. But the e2e job, which was the critical path, didn't get faster, because its time was waiting, not compute. Everything after the cutover came from finding where the e2e waits were and removing them.

## 2. Timeline

All times UTC.

### Before Phase 4 (infra groundwork, 2026-11-16 and 17)
- infra-mk3 #837–#841: harbor-operator, and a Harbor project with a push robot per CI project.
- infra-mk3 #851–#868: registrygate deployed as the CI registry proxy, in stages.
  1. ghcr.io interception for infra-mk3's own docker builds.
  2. Per-project Harbor proxy caches and Harbor pushes.
  3. quay.io, mirror.gcr.io and Docker Hub, then public ECR.
  4. Interception on by default for every CI project, GHCR pushes with the account's PAT, a shared git-clone Task and a `harbor_host` parameter.
  - Gotchas from this stage are in memory `project-ghcr-proxy-agent-project`:
    - Harbor's realm is named after its Service;
    - Harbor rejects the quay adapter for proxy caches;
    - harbor-operator bugs #198–#200;
    - cert-manager doesn't reissue a CA when only nameConstraints change.
- infra-mk3 #869 and #877–#880: the Project Zomboid image moved to a Tekton build, which pushes it to Harbor. That work found **the kata guest boot limits**: the guest kernel sizes `tcp_mem`, threads and nproc from the 256 MiB boot memory, which capped download speed in builds. infra-mk3 #877 fixed it with kernel_params sysctls.

### Phase 4: CI on Tekton (2026-11-18 05:38 to 2026-11-19 01:03, about 19.5 h of wall clock)
- **05:38:** the operator created tracker #175, with the checklist AC-4-01…09 in the epic body, and milestone 4.
  - Owner-approved goal: the shortest wall clock to the required check, not a lift-and-shift.
  - Constraint: agents never change infra-mk3. They file `needs-human` + `area:ops` issues instead.
- **infra-mk3 #881 and #882:** onboard `ci-registrygate`, with a 48 GiB quota, a concurrency limit of 3 and a 30Gi Docker cache volume.
- **Design review (#180), then the design doc `docs/design/phase-4.md`:** the baseline numbers, a one-pod-per-run "stage runner" (`scripts/ci/stages.sh` runs every stage in parallel in containers of a CI image built from `flake.nix`, inside one dind sidecar), the golden-cache pattern, sizing from measured peaks, a risks-first e2e prototype, and the cutover steps.
- **infra-mk3 #883:** kind in the docker Task (`mknod /dev/kmsg`, cgroup v2 delegation through the dind wrapper) and an `output` result for later tasks.
- **07:54:** first cold PR run, 11.2 min. 137s of it was the cold CI image build, and e2e `go test` took 380s, the same as on GHA.
- **~11:21:** interim numbers: PR p50 9.1 min. A stage-selection bug had meant earlier "runs" ran no stages (#194).
- **Owner questions during the afternoon**, which led to new work:
  - "Why no speedup with 48 GiB and lots of CPU?" e2e looked latency-bound.
  - "Why do the tests take so long?" Serial tests and `TestMain` installs.
  - "Aren't images pulling through Harbor?" Not from kind: the kind node's containerd bypasses dind's interception.
  - Results: #199 (preload kind images through dockerd), #200 (walkthrough on its own kind cluster, in parallel), #198 (required check).
- **PaC stuck-pending runs** (a 404 when moving the check run to in_progress) were fixed by the PaC v0.54.0 that ships with Tekton operator 0.82.0 (infra-mk3 #895). The operator then blocked on two new CRDs (`shipwrightbuilds`, `tektonkueues`) that the CRD Kustomization didn't install (infra-mk3 #897).
- **KubeVirt 1.10 upgrade (owner, infra-mk3 #896):** live-migrated the Coder VMs at 21:20 and broke `coder ssh` (tailnet). The operator reached the VM through `virsh qemu-agent-command` (QGA). Restarting the Coder agent kills the PM loop, because the scheduler runs in the agent's cgroup.
- **21:41:** final table, PR p50 9.1 < 9.5. The owner accepted n=2 master runs. Cutover #197: `ci.yml` removed, and branch protection requires only the Tekton check.
- **Phase-end security review and bug hunt:** #205 (high: the scheduler's `/retest <name>` is ignored by PaC), #206, #207, #208 (shell injection in `up.sh`), #209 (the golden volume grows with every image bump). Then #191 (overlay mount EIO in e2e) and #218 (cleanup step needed bash) broke master for a while.
- **2026-11-19 00:33:** v0.4.0 released. **01:03:** Phase 4 complete, PM paused, because Phase 5 has no design.
- **Cost:** 102 agent jobs, **$42.53**, 6.1 agent-job-hours (planner $13.05 over 65 runs; workers $22.11 over 31 jobs; design-review $2.18; bug-hunt $2.28; security-audit $1.73; release-manager $1.09).

### After Phase 4: owner-driven speed work (2026-11-19 01:00–09:30)
- **#202 (preload) made e2e slower at first** (532s on a cold cache). The worker skipped the before/after measurement the issue asked for, and the reviewer merged anyway. Later runs were fine.
- **"Why is e2e still 364s?":**
  - The operator measured `up.sh` at 55s warm in the VM, and about 110s per stage in CI.
  - Disk usage was ~21 GB of the 30Gi cache during runs, which matched the #191 overlay EIO. Fixed by infra-mk3 #900 (50Gi).
- **Is e2e on every PR right?** There's no merge queue: it's a user account, not an org. CI time drives the issue tail, and waits over 5 minutes expire the workers' prompt caches, which raises cost. So e2e stays on PRs, path-filtered (already in `changes.py`).
- **"Several projects need kind; can this be shared?"** vcluster was rejected: test pods would run on the real cluster, privileged dind would need allowing there, and every test would be subject to Kyverno, Cilium and PSA. Instead, kind-in-kata becomes a platform feature of the shared docker Task:
  - **infra-mk3 #904:** dind writes `/run/ci-kind/`, with hosts, `certs.d` with registrygate's CA per host, and a kubelet credential provider that reads the pod's rotating registrygate token. The `ci-kind-config` wrapper, with yq brought in as an image volume, merges it into any kind config.
  - **infra-mk3 #905:** yq is also mounted into dind, so stage containers can use it.
  - The owner pushed back on "not transparent" and on the runc-wrapper idea ("extremely messy"), and asked about insecure mirrors. The conclusion: TLS interception means the CA must get into the node's containerd somehow, and only the node config, the node image or the runtime can do that. A one-line opt-in wrapper was the accepted compromise.
- **CI-speed round 1 (06:01–07:40), 7 issues, one at a time:**
  - #222 (create the cluster while images build);
  - #223 (build e2e images once);
  - #224 (kind pulls through Harbor via `ci-kind-config`, dropping the preload);
  - #228 (log every wait with its duration);
  - #229 (parallel `TestMain` installs);
  - #230 (`t.Parallel` for independent tests);
  - #231 (faster polls).
  - Cost: 27 jobs, **$6.67**, 1.6 job-hours.
  - The biggest single win was **#230: e2e went from about 5:06 to 3:20**.
- **The DNS investigation (08:00–08:25):**
  - **Symptom:** a cold kind cluster failed with `registry.k8s.io` DNS timeouts.
  - **Cause:** cluster-wide, 0.1–1% of *cross-node* DNS lookups stalled 5–10s, and same-node lookups never did. The Intel X710 (i40e) NICs were dropping packets with `rx_missed_errors` at 512-of-8160 rx rings, and the drops rose with CI traffic.
  - **infra-mk3 #908:** rings raised to 4096, applied node by node with `topf`, with no link flap.
  - **Result:** after the fix, zero stalls in 48,000 cross-node lookups under CI load, and `rx_missed` flat. About one Cilium DNS-proxy timeout a minute remains (section 6.5).
- **infra-mk3 #909:** a kind node image cache. Each node's whole `/var/lib/containerd` lives on the build's Docker volume, keyed by node container name and seeded from the node image. **infra-mk3 #910:** `ndots:1` in Tekton's default pod template.
- **#237 (08:33–08:41):** registrygate uses the cache. Controlled warm runs: total 270–277s.
- **CI-speed round 3 (from 09:17):**
  - #239: skip the 42s namespace teardown in CI;
  - #240: create clusters while images build;
  - #241: CoreDNS without a rollout, 11s;
  - #242: measure, then shorten Harbor's 63s install;
  - #243: prove mirrored pulls without polling Harbor's listing, 18–20s.
  - Two parallel chains. In progress when written.

Rough total agent spend for the migration: **~$50** (Phase 4 $42.53 + round 1 $6.67 + #237 $0.55; round 3 not counted). The earlier product phases 1–3 cost $131 over 268 jobs, for comparison.

## 3. Where the time actually went (the technical story)

### 3.1 GitHub Actions baseline
- **Setup:** every job spent 2.0–2.7 min in `./.github/actions/nix-dev-shell` (Nix install, store restore, Go cache restore) before doing any work. Six parallel jobs each paid it.
- **e2e was the critical path:** 41s `kind create`, 10s image builds and load, then 377–446s of `go test`. The longest test, the admin-docs walkthrough, took 157–163s.
- **Runners:** GHA runners have 4 vCPUs. Queueing was negligible for PRs (0.1 min), and up to 6.2 min p90 for master pushes waiting on each other.

### 3.2 What the Phase 4 design fixed
- **No per-job setup:** one pod, one VM, one dind. A CI image built from `flake.nix` (`scripts/ci/ci-image.sh`) stays cached on the golden Docker volume. A cache hit takes 2s; a cold build 118–137s.
- **All stages at once:** they run as containers in one dind, inside a 32-vCPU kata VM with 14 GiB for dind (sized from the summed cold peaks of 13.5 GiB, warm 9.3 GiB). unit, integration, lint and generate went from 2.2–3.5 min to 0.1–1.3 min.
- **Golden cache:** a per-run copy-on-write clone of the project's latest snapshot, promoted only from successful default-branch push builds. It gives warm Go and Docker caches with no network transfer.
- **Not fixed:** e2e still took about 8.4 min, and set the whole run.

### 3.3 Why the extra hardware didn't help e2e
- **My first claim:** the stage table showed e2e at ~0.1 cores and a 0.3 GiB peak, so I said e2e was "latency-bound". **That table only measures the stage container** (`go test`, `kubectl`, `helm`). The kind node containers, which run the API server, etcd, Harbor and so on, are outside its cgroup. cAdvisor can't see inside kata VMs either, so no cluster metric showed CI CPU at all.
- **The direct measurement:** sampling `/proc/stat` and `docker stats` from inside the build VM, during a run.
  - Setup phase, about 2 min: 2–5 of 32 cores, with 4–14% iowait. The kind nodes peaked at 100–300%.
  - Test phase, about 3.5 min: 0.2–1 core and 0–2% iowait. Each kind node sat at 10–30% (an idle control plane), and the test processes at about 0%.
- **So the tests were waiting, not working:**
  - serial tests;
  - serial `TestMain` installs, each with `--wait`;
  - Helm `--wait` and readiness probe periods;
  - `Eventually` polls, for example Harbor listing a proxied image, which it records in the background after serving the pull;
  - namespace deletion with finalizers;
  - a CoreDNS rollout restart.
- **Lesson:** profile the test suite's waits *before* designing for speed. The wait logger (#228) should have been the first issue of Phase 4, not the eighth of the round after it.

### 3.4 kind inside dind inside kata
- **Four levels of nesting:** Docker inside kind, inside dind, inside a kata VM.
- **Requirements:**
  - `/dev/kmsg` made with mknod, since kata gives privileged containers no devices;
  - cgroup v2 controller delegation through the dind image's wrapper;
  - for the image cache, mounts from paths on dind's side, since dockerd resolves `-v` there and not in the step.
- **kind's node containerd uses none of the pod's settings:** neither `/etc/hosts` (the hostAliases), nor dockerd's `certs.d`, nor the credential helper. Without `ci-kind-config`, every image pull inside kind went straight to the internet, uncached, every run.
- **`kind load` fails on multi-platform images** in Docker's containerd image store, because it imports all platforms. The preload had to use `docker save | ctr images import --digests --base-name`.
- **No exec into a kata sidecar:** it fails with cgroup EBUSY (the dind wrapper's cgroup delegation). Exec into the step container instead, and use `DOCKER_HOST`.
- **Port-forward to kata pods doesn't work** (an older memory).

### 3.5 Image pulls inside kind
- **#227's runs** downloaded 1.2 GB compressed, in 177 blobs plus 60 manifests, per run for both clusters.
- **"27 MB/s" was a misleading average.** Single-blob bandwidth was fine on every hop:
  - S3: ~500 MB/s;
  - Harbor core: 130–185 MB/s;
  - the full path from the build pod through registrygate: 150–245 MB/s, and ~290 MB/s across 4 parallel downloads.
- **The real cost was per-request latency.** Each blob waits ~130–350ms before its first byte, mostly inside Harbor (core → registry → S3 through the gateway at `10.34.0.1` with TLS). 111 blobs under 1 MB took 22s of request time and carried almost no data.
- **The kubelet's serial image pulls** (`serializeImagePulls: true` is the default) made those waits add up. #235 set it to false.
- **The preload had looked "faster"** than kind-through-Harbor only because the first comparison runs overlapped one another. Comparable runs showed parity.
- **The image cache (infra-mk3 #909) removes the per-run download and unpack entirely.**
  - Warm `kind create`: 28–36s, against 41–56s cold.
  - Pods start with images "already present".
  - About 1–2.9 GB per node.
- **Things that don't work for the cache:**
  - **Sharing only the content store:** containerd's GC deletes blobs its fresh database doesn't reference, and mounting over the content store hides the node image's built-in images.
  - **An empty `/var/lib/containerd`:** it hides kind's system images, so the node tries `registry.k8s.io`, which isn't intercepted, and the cluster never comes up. Seeding from the node image fixes it, in about 6s.
  - **Locks:** not needed. Docker's unique container names already prevent two nodes sharing a directory, and my first lock design made same-name re-creates within one build go uncached.

### 3.6 Disk
- **At 30Gi,** the cache volume filled mid-run: the CI image (~3.4 GB), Go caches (~4 GB), the kind node image, two clusters each with ~14 preloaded images, and the build cache allowed to grow to 60% of the volume.
- **Write-back errors then broke overlay mounts in kind** ("Cannot mount volatile when upperdir has an unseen error"), as #191 showed.
- **The fix was 50Gi** (infra-mk3 #900). The kind image cache adds about 5.5 GB per project with two clusters.

### 3.7 DNS
See section 6.5 for the open part. What was learned:
- `ndots:5` with three search domains means up to 8 queries per lookup of a name like `ghcr.io`. kind nodes and every container on dind inherit the pod's `resolv.conf`, and they generated most of the CI DNS load. Fixed by `ndots:1` in Tekton's default pod template (infra-mk3 #910).
- **The cluster-wide fallback DNS policy** `cluster-default-kube-dns-egress` allows `kube-system/kube-dns`, but CoreDNS runs in `networking`. So a namespace without its own DNS policy can't resolve at all.
- **The NIC fix (#908) was found because the operator chased a kind failure.** The DNS stalls had been there for a long time (the drop counters went back to boot) and affected the whole cluster, not just CI.

### 3.8 PaC and Tekton
- **Stuck `PipelineRunPending` runs:** before PaC v0.51 the check-run update got a 404. Fixed by PaC v0.54.0 (operator 0.82.0).
- **Operator upgrades can need new CRDs:** the CRD Kustomization lists raw per-file URLs pinned to a commit, so new CRDs must be added by hand. Otherwise the operator blocks on its informers.
- **`/retest <generated PipelineRun name>` is ignored by PaC** (#205). `/retest`, `/test` and ready-for-review each start new runs, so one push plus a ready-for-review plus a `/retest` gave 3 runs at once on one commit.
- **GitHub keeps one check suite per app and commit,** so re-runs replace the earlier check run, and `measure-ci.py` can't count them separately.
- **Pipelines are inline in `.tekton/`,** using the cluster resolver for `ci-tekton` Tasks only. Remote tasks, the hub and git resolvers are off.
- **Tekton has one pod per Task.** StepActions, steps and sidecars run in that pod. Every shared CI feature should go into the one build pod, through files, env and mounts the docker Task provides, never as its own pod. The owner's concern was chaining features that each want a pod.

## 4. How the agent-project process did

### 4.1 What worked
- **Throughput was high once an issue was well scoped:**
  - round 1: 7 issues in ~1.6 h;
  - #237: about 8 minutes from worker start to merge;
  - the #222 and #225 pair: about 8 minutes too.
  - Most of the time was CI wall clock and waiting for the operator or owner.
- **The design phase with a risks-first prototype worked.** The prototype found the cold image build cost and the 380s `go test` floor before the pipeline was built.
- **A frozen acceptance checklist (AC-4-01…09) gave a clear finish line.** Phase 4 closed cleanly with evidence per item, a release, and an end-of-phase security review and bug hunt that found real defects (#205 high, #208 injection, #209 unbounded growth).
- **The "agents never touch infra-mk3" rule did keep the owner in the loop** for every infra trade-off: quota, concurrency, cache size, kind support, the NIC change, ndots.
- **The planner handled odd states well:**
  - it noticed when a PR merged against a hold and reported it honestly;
  - it noticed the scheduler hadn't reloaded its phase, and asked for a restart instead of working around it;
  - it re-paused itself correctly at the end of each round.
- **Splitting work into blocked_by chains** kept merge conflicts away and measurements interpretable.
- **The wait logger (#228)** turned "e2e is slow" into a ranked list of fixed waits. That list produced round 3.

### 4.2 What didn't work, or caused rework
- **Measurement requirements were ignored over and over.** Issues asked for before/after stage times in the PR body (#202, #225, #226, #233, and #230/#231 in part), and reviewers merged without them, even after an operator note on #25 saying not to. Workers said they "can't see CI". In fact the stage tables are in the `stage:` check runs, readable through `gh api .../check-runs`. Reviewers merge on green, so this is a gap in the reviewer playbook: "measurement in the PR body" isn't a merge gate.
- **Overlapping CI runs made every per-PR measurement noisy,** by 30–60s, 10–15% and more. Agents and the planner made it worse with `/retest` and `/test` to "get more samples", and the planner admitted the mistake. Fair numbers needed the operator to run back-to-back PipelineRun clones by hand (section 5).
- **Stale worker sessions:**
  - A worker resumed with old context doesn't re-read new instructions on the issue or PR.
  - The #224 worker (started 06:41) never saw the 06:50 operator instruction. It looped on `/retest` and `/test`, then marked the PR ready with auto-merge already on, and it merged against an operator hold.
  - **A `pr:N` hold doesn't stop a resumed worker;** only an `issue:N` hold does. Draft status was undone by the worker.
- **The scheduler reads `.pm/scheduler.json` only at startup.** Changing `current_phase` needs a restart. SIGTERM to `scheduler.py` also ends `scheduler-loop.sh`, and with it the tmux session `pm`, because the window runs the loop directly. Restart from `coder ssh` so the agents keep their credentials.
- **Stale operator instructions in `.pm/state.md`:** "Pause again when #231 closes" and "when #237 closes" lines survived into the next round. Both issues were already closed, so the planner could have paused straight away. Instructions written as "until X" need removing when X happens, or a round ID.
- **The milestone and phase gate:** the scheduler only starts issues in the current phase's milestone (`later_phase_work: false`). Each ad-hoc round meant reopening milestone 4, setting the phase back, restarting, and re-pausing afterwards. The "phase" model doesn't fit small follow-up rounds.
- **A worker dropped the measurement on #202,** and the reviewer merged a change that made e2e slower on a cold cache. Nobody noticed until the operator looked.
- **Agents can't see cluster-side evidence:** registrygate's own access log, CoreDNS logs, the NIC counters, kata VM CPU. The operator had to check every "is it really going through the mirror" question by hand.
- **The PM's GitHub token can't `gh run rerun`** (an older note), and PaC re-runs need `/retest` comments, which then caused the overlap problem above.
- **The VM broke during an owner infra change** (the KubeVirt live migration), and the operator's workaround (QGA, restarting the agent) killed the PM loop. A backgrounded `rm .pm/PAUSE` command left over from before the outage ran later and unpaused the PM unexpectedly. It was caught immediately.

### 4.3 Operator (my) mistakes and course corrections
I'm recording these honestly, so the next run can avoid them:
1. **"e2e uses 0.1 cores, so it's latency-bound":** right conclusion, wrong evidence (section 3.3). The direct VM sampling should have come first.
2. **"Both stages rebuild the images":** wrong. The second stage found them cached behind the lock. The real cost was the wait.
3. **Proposed a runc wrapper for transparent kind mirroring.** The owner called it "extremely messy" and it was dropped. I should have led with the explicit opt-in.
4. **"27 MB/s per download is slow":** an average dominated by small blobs. The bandwidth was fine.
5. **"#224 is 20–40s slower" and the stop-and-report:** that came from overlapping runs. The comparable runs showed parity. The hold was right, but the stated cause was wrong.
6. **"registry.k8s.io lookups time out from CI":** it wasn't blocked. That cold-cache failure was the empty containerd store. Chasing it still found the real, cluster-wide NIC problem.
7. **Two wrong theories in the DNS investigation,** each tested and dropped: Cilium DNS proxy transparent mode with glibc's parallel A/AAAA sharing a socket, and socket-LB reverse NAT. The same-node versus cross-node test settled it in one run. It should have been the second test, not the fifth.
8. **Scripting slips while prototyping:**
   - a `set -u` unset variable;
   - a perl multi-line edit that wrote at the top of `task.yaml`;
   - the script put into the Task's `image` parameter;
   - `docker run -v` from the step side;
   - busybox as root against `runAsNonRoot`.
   - All were caught by running the prototype, which is the argument for always prototyping in a throwaway TaskRun before opening an infra PR.
9. **The first image-cache lock design** made same-name re-creates within one build go uncached. The fix was to drop the locks.
10. **I left `kubectl debug` ephemeral containers** in production pods (the Harbor registry, registrygate, CoreDNS pods). They're harmless and exited, but they stay in the pod specs until restart.

### 4.4 How the owner's involvement drove things
Most of the real gains came from the owner asking "why" until the answer was a measurement:
- "Why no speedup?"
- "Why do the tests take so long?"
- "Aren't images pulling through Harbor?"
- "Why does every test reinstall?"
- "Where does the time go?"
- "Is this a one-time or a recurring cost?"
- "Why does the cluster start with an empty image store?"
- "Is Harbor required, or would a generic registry do?"

The PM agents never raised these questions themselves. Within the frozen checklist, "PR p50 below GHA" was met at 9.1 vs 9.5, and the PM stopped there. That's correct behaviour under the skill's "agents can't raise the bar" rule, but it means extra speed needs an owner or operator who keeps asking.

Owner decisions along the way:
- accepted n=2 master runs for AC-4-06;
- e2e stays on PRs, path-filtered;
- no vcluster;
- an explicit opt-in kind wrapper rather than transparency;
- keep #227 after the comparable data;
- parallel kubelet pulls;
- the image cache;
- ndots;
- the NIC rings;
- rounds 1–3.

## 5. Measuring CI time properly

What finally gave trustworthy numbers:
- **Clone a real PipelineRun.** Take its definition (`kubectl get pipelinerun <push run> -o json`), keep only `apiVersion`, `kind` and `spec`, set a `generateName` and a label of your own, drop `spec.pipelineSpec.finally` (the `report` task, so nothing posts to GitHub), drop the PaC labels (so the golden-cache promoter ignores it), and set the `revision` param to the commit under test.
- **Run them one at a time.** Wait until no PipelineRun is running in the namespace, then start the next. Alternate the before and after commits (old, new, old, new...) so drift from cluster load spreads evenly. Three of each was enough: runs within a set agreed to within 5–15s.
- **Read the times from the `ci` TaskRun's `output` result,** which has each stage's seconds, plus `completionTime - startTime`.
- **Prefer master push runs** for ad-hoc numbers. PR runs overlap more.
- **Watch for the warm cache.** The golden volume only refreshes from successful default-branch push runs, so the first run after a cache-related change is cold. Wait for the master push run of the merge, then measure.
- The scripts are in the operator scratchpad (`timing-runs.sh`, `warm-runs.sh`, `timing-template.json`). They aren't committed anywhere. They should become a reusable tool, probably in infra-mk3, or as a Tekton MCP tool.

Pitfalls:
- **`measure-ci.py`** (in registrygate) reads GitHub check suites. It's good for p50/p90 over many runs, but it can't count re-runs, it includes queue time, and overlapping runs inflate it.
- **The stage table's CPU and memory column** covers only the stage container, never the kind nodes.
- **cAdvisor has no container metrics for kata pods,** so VictoriaMetrics can't show CI resource use. Sample from inside the VM instead (`/proc/stat`, and `docker stats` through `DOCKER_HOST`).
- **Single-run comparisons are noise,** up to 60s.

## 6. Infra state after the migration, and open items

### 6.1 What the CI platform now gives every project
- **The `ci/project` chart:**
  - a `ci-<name>` namespace, quota, concurrency limit and Docker cache volume size;
  - Harbor project and robot;
  - registrygate interception, on by default: per-project Harbor proxy caches for ghcr, quay, mirror-gcr, dockerhub and ecr-public, Harbor pushes, and optional GHCR pushes;
  - a `ci-build` ServiceAccount;
  - netpol: internet with private ranges excluded, Harbor through the internal gateway, registrygate, GitHub FQDNs.
- **The shared `docker` Task** (`cluster/gitops/ci/tekton/docker/task/`):
  - a privileged dind sidecar inside kata, with storage on a block volume cloned from the golden snapshot;
  - registrygate CA and hosts and the credential helper;
  - kind support: `/dev/kmsg` and cgroup delegation;
  - `ci-kind-config` for kind nodes through registrygate, plus the per-node image cache with `--name` and `--image`;
  - an `output` result;
  - `yq` mounted in both the step and dind.
- **Defaults** from TektonConfig: `runtimeClassName: kata`, `ndots:1`, the `ci-build` ServiceAccount.
- **The golden-cache promoter:** it snapshots the docker volume of successful default-branch push runs.
- **Talos:** X710 rx rings at 4096 (`talos/patches/all/28-nic-rings.yaml`), and kata guest kernel limits sized for real memory (#877).

### 6.2 registrygate's CI design, reusable as a pattern
- **One PipelineRun and one `ci` pod.** `scripts/ci/stages.sh` runs every stage in parallel, in containers of a CI image built from the flake, inside the one dind. Each stage records `memory.peak` and CPU time.
- **`changes.py` path rules** pick the stages for PRs; master runs them all.
- **A separate `test-guard` pod,** the only one with the GitHub token besides `report`. It runs no repository code.
- **A `report` finally task** creates one `stage: <name>` check run per stage, with its log, so failures show on GitHub.
- **`OWNERS`** lets Renovate's PRs run.
- **The release stays on GHA:** multi-arch builds under QEMU in kata would be slow, and it would need extra credentials in builds.
- **Cutover sequence:** run Tekton alongside → require both → remove `ci.yml` (the owner drops `checks` from branch protection first) → require Tekton only.

### 6.3 Remaining time on registrygate's critical path
From the wait log of warm run `timing-warm-k9q89`. Round 3 is working on these.
- **The walkthrough stage, 226s:**
  - `up.sh`: 45s (kind create 41s under load);
  - Harbor `helm install --wait`: 63s;
  - CoreDNS rollout: 11s;
  - the test itself: 114s, including 20s polling Harbor's listing;
  - teardown: 42s, wasted in CI.
- **About 50s outside the stages:** mostly the 23s shared image build, which both e2e stages wait for.
- **Pod start:** ~9s (volume clone plus kata boot), which is fine.
- **Not measured: queue time** under `concurrencyLimit: 3` with several agents opening PRs. It counts toward the issue tail.

### 6.4 Harbor in e2e
- registrygate is generic: any Distribution-API registry, and any path-prefix mirror. Harbor is in e2e because it's the deployment target, and only real Harbor reproduces its quirks:
  - realm and `Location` headers named after its Service or external URL, which is why `aliasHosts` exists;
  - background caching of proxied images;
  - robot pushes.
- The walkthrough follows the admin guide, which uses Harbor, so it needs Harbor anyway. The owner chose to keep Harbor and make its install faster (#242), rather than swap in a fake.

### 6.5 Open: the residual DNS-proxy timeouts
- About 1 a minute cluster-wide: `Timeout waiting for response to forwarded proxied DNS lookup`, for in-cluster names, all cross-node. It only happens for endpoints with L7 DNS rules. With L4-only policy, cross-node lookups had zero stalls after #908.
- **Ruled out:** CoreDNS (2ms p99, slowest answer 89ms, in and out UDP counts match), policy drops, map pressure, host counters.
- **Suspected:** Cilium 1.20.4's transparent DNS proxy (`dnsproxy-enable-transparent-mode: true`, `proxy-use-original-source-address: true`) across nodes.
- A handoff writeup for another agent exists (in the session; not committed).

### 6.6 Other loose ends
- `kubectl debug` ephemeral containers remain in pod specs until those pods restart: the Harbor registry `b5k7v`, registrygate `n4ncr`, and the three CoreDNS pods.
- **CoreDNS has a 100m CPU limit,** against the no-CPU-limits rule. It isn't throttled today, but it's a policy violation.
- **The cluster-wide DNS fallback policy points at `kube-system`,** but CoreDNS is in `networking` (section 3.7).
- **A CI-time measurement tool** (section 5) should be committed.
- **Old Harbor `project-zomboid` project and robot** still to delete (from the PZ migration).
- Timing scripts and prototypes live only in the operator scratchpad.

## 7. Observations for migrating other projects
Raw, not yet a playbook:
- **Measure first.** Get the GHA baseline per job and per step, the setup cost per job, and the test suite's own waits. Cheap instrumentation like `e2e-wait:` lines with durations helps a lot. Decide what's waiting and what's working before sizing anything.
- **Hardware only helps the working part.** On GHA the visible cost was per-job setup. On Tekton the remaining cost was waiting inside e2e. More CPU or memory changed neither.
- **The biggest wins, roughly in order:**
  1. one pod and one VM for all stages, with a prebuilt CI image (no per-job setup);
  2. parallel tests inside the e2e suite;
  3. persistent caches: the golden Docker volume, then the kind node image cache;
  4. removing CI-only waste: teardown of throwaway clusters, rollouts, serial installs;
  5. infra fixes that help everyone: NIC rings, ndots.
- **Projects with kind:** use `ci-kind-config --name ... --image ...` from day one. Keep cluster names stable between builds, since they key the cache. Expect the first run after the change to be cold. Remember that kind in kata needs the docker Task's settings, and that stage containers must mount `/run/ci-kind` and `/opt/ci-kind`.
- **Size the Docker cache volume for the CI image, the Go or other caches, the kind node image and the kind caches together.** Running out shows up as odd overlay or EIO failures, not as "disk full".
- **Agents' PRs will overlap,** so the concurrency limit and quota decide both queueing and the noise in measurements. One run per head commit has to be enforced, not just asked for.
- **Path filtering:** e2e stays on PRs, because the owner has no merge queue on a user account.
- **The release can stay on GHA** if it's rare and multi-arch.
- **For agent-run migrations,** the agents need read access to their own CI logs. The Tekton MCP server exists in toolgate; check the VM agents can use it. They also need some way to read cluster-side evidence (proxy logs), or each verification lands on the operator.

## 8. Observations for the agent-project skill
Raw, not yet a skill change:
- **Make measurement a merge gate.** If an issue's acceptance has numbers, the reviewer must not merge without them in the PR body. Better: the `report` task or the scheduler posts the stage table to the PR automatically, so agents don't have to fetch it.
- **One CI run per head commit, enforced in the scheduler:** reject or ignore `/retest` and `/test` unless a run failed for a non-code reason. Avoid opening a PR ready for review and pushing at the same time.
- **Re-read instructions on resume:** a resumed worker session should re-read its issue's and PR's new comments before acting. Hold semantics need fixing too: `pr:N` should also block the worker on the linked issue, and a worker shouldn't be able to undo a draft or a hold.
- **Scheduler config reload:** reload `.pm/scheduler.json` every poll, or on SIGHUP. Don't kill the tmux session when the loop exits, so it stays restartable.
- **Ad-hoc rounds need a lighter mechanism** than reopening a phase milestone: for example a "round" label or milestone, and `later_phase_work` for listed issues only.
- **Expire operator instructions.** Lines in `state.md` should carry an ID and an end condition, and the planner should delete them when the round ends.
- **Profile before optimizing:** for any phase whose goal is speed, the first issue should be instrumentation (like #228), and the design should be based on its output.
- **Speed goals need someone to push past "below baseline".** Under a frozen checklist, the PM stops at the first number that passes. If the owner wants "as fast as reasonable", the checklist should say so as a target, or the operator should plan rounds after the phase, as happened here.
- **Cost is low compared to the time:** about $50 of agent spend for the whole migration. The real limits were owner and operator attention, and CI wall clock.
- **Prompt cache economics:** workers waiting more than about 5 minutes for CI lose their cache, so CI time directly drives agent cost as well as the issue tail. Cutting CI time pays for itself.
- **Keep the infra boundary,** with "operator implements, owner approves" for infra-mk3. It worked and kept the owner in control. The operator should prototype infra changes in a throwaway TaskRun before opening a PR. Every infra PR here was prototyped, and every prototype caught at least one bug.
- **VM fragility:** an owner infra change (KubeVirt live migration) can break the PM's VM. The skill should document recovery (QGA, restarting the agent and the PM loop) and pause the PM before owner maintenance.
