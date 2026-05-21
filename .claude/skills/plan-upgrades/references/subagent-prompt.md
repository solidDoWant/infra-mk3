# Per-Dep Research Subagent Prompt Template

Used by the `plan-upgrades` skill to dispatch a research subagent for one dependency. Subagent type: `Explore`.

## Placeholders

The skill substitutes these before dispatch:

- `{{DEP_NAME}}` — dependency name
- `{{CURRENT_VERSION}}` — current pinned version
- `{{TARGET_VERSION}}` — computed latest-stable target, or user-specified target. May be `(determine from policy)` if the subagent should compute it.
- `{{POLICY}}` — verbatim policy text from `version-policies.md` for this dep
- `{{COMPONENT_NAME}}` — name of the cluster component being upgraded (e.g. `authentik`)
- `{{COMPONENT_PURPOSE}}` — one-sentence description of what the component does
- `{{KUBERNETES_VERSION}}` — current cluster Kubernetes version
- `{{PARENT_CONTEXT}}` — empty string for direct-dep dispatches; for sub-dep dispatches, a `## Parent context` section explaining the parent dep, the induced trajectory, and the no-recursion constraint
- `{{CANDIDATE_CONSUMERS}}` — output from cluster-wide grep for this dep (file paths + ~2 lines context per hit)
- `{{REPO_REFERENCES}}` — local grep hits for issue/PR/TODO comments mentioning this dep in the target component's directory
- `{{COMPONENT_NETPOLS}}` — file paths of `netpol*.yaml` / `*netpol.yaml` files within the target component's own directory; the subagent reads contents directly

## Prompt body

````
Research the upgrade path for the dependency `{{DEP_NAME}}` from version `{{CURRENT_VERSION}}` to `{{TARGET_VERSION}}`.

This dep is used by the cluster component `{{COMPONENT_NAME}}` ({{COMPONENT_PURPOSE}}). The cluster runs Kubernetes `{{KUBERNETES_VERSION}}`.

{{PARENT_CONTEXT}}

## Versioning policy

{{POLICY}}

## Candidate consumers

The skill grepped the cluster for references to this dep. Each hit below is a file path and ~2 lines of context. Some may be false positives. For each: read the file as needed to decide whether it is a real consumer, and if so, characterize the interaction (OIDC client, proxy forward-auth target, direct API call, mTLS peer, ConfigMap reference, etc.).

{{CANDIDATE_CONSUMERS}}

## Repo references

Comments / TODOs / issue links found in the target component's directory that mention this dep:

{{REPO_REFERENCES}}

## Component netpols

The following `netpol*.yaml` files belong to the target component. They are the most common edit target during upgrades — when a new version adds/removes pods or changes traffic patterns, these are usually what break. Read them and cross-reference against your structural and release-notes findings.

{{COMPONENT_NETPOLS}}

## Method — apply to every step in the upgrade path

Do this for **every** step, including patch-only bumps. Projects routinely ship new pods, new ports, new outbound calls, and new metrics endpoints in patch releases without calling them breaking — but they still require netpol edits. Do not short-circuit netpol analysis based on the size of the version bump.

For each step:

1. **Chart structural diff** (for chart-deployed deps): fetch the chart at both the "from" and "to" versions of this step. Prefer `helm pull <repo>/<chart> --version <v> --untar` if helm is available; otherwise fetch the chart tarball directly from the repo's `index.yaml` (HTTP repos) or via `oras pull` / direct HTTPS for OCI registries, and extract. Render templates with default values (`helm template`). Diff the rendered output and note every:
   - Added/removed/renamed `Deployment`, `StatefulSet`, `DaemonSet`, `Job`, `CronJob`
   - Added/removed/changed `Service` ports and selectors
   - Added/changed `containers`, `initContainers`, sidecars (including ports)
   - Added/changed `ServiceAccount` references (may affect identity-based netpol rules)
   - Chart-shipped `NetworkPolicy` / `CiliumNetworkPolicy` resources
   - Env vars or args that imply outbound endpoints (URLs, hostnames, ports)
   - New `ConfigMap`/`Secret` references whose contents likely include endpoint URLs
2. **Release-notes keyword scan**: search this step's release notes for the keywords `network`, `egress`, `ingress`, `port`, `sidecar`, `endpoint`, `webhook`, `metrics`, `proxy`, `outbound`, `connection`, `dns`, `hostname`.
3. **Issue tracker scan**: search the project's issue tracker for issues filed against the target version range matching `network policy`, `connection refused`, `egress denied`, `firewall`, `cilium`.
4. **Cross-reference** every structural / release-notes / issue finding against `{{COMPONENT_NETPOLS}}` and the netpols of any real consumer identified in `{{CANDIDATE_CONSUMERS}}`. Decide for each: does the existing rule still match? Does a new rule need to be added? Does an existing rule no longer apply?

For non-chart deps (raw images, operator CRDs), skip step 1 and rely on steps 2–4 plus a source-code search for new network calls.

## What to produce

Return a structured markdown report with these sections.

### Latest stable target

The version you computed as latest stable per the policy. Brief reasoning if the choice is non-obvious. If the prompt gave you a fixed target, restate it and confirm it satisfies the policy.

### Upgrade path

The ordered list of version steps from current to target. Apply this rule by default:

1. Latest patch on the current minor
2. Latest minor on the current major
3. First version (per policy) of the next major
4. Repeat steps 2–3 until reaching the target

But honor the policy's `skip-allowed` rules. If the policy permits skipping minors, collapse the path accordingly. If the policy requires sequential traversal, do not collapse.

### Sub-dependencies

List meaningful sub-deps bundled with this dep that have their own version stream worth analyzing separately. A sub-dep is "meaningful" if **all** of:

- It has its own release notes / changelog.
- It is likely to introduce user-visible changes (breaking changes, security fixes, notable features, behavior changes) that a cluster operator would want to know about.
- It is implicitly pinned by the parent version, not independently bumpable.

For each meaningful sub-dep:

- **Name**
- **Trajectory**: the sub-dep's version at each parent version in the upgrade path. e.g. `parent 1.16.4 → containerd 1.7.13`, `parent 1.17.3 → containerd 1.7.18`.
- **Source**: where you found this information (parent's release notes, chart `values.yaml` / subchart pins, image-layer inspection, upstream docs, etc.).

Examples of meaningful sub-deps:

- Talos → containerd, Linux kernel, runc, kubelet
- Rook → Ceph (the server image, not the chart)
- A Helm chart with a subchart that ships a separate version stream

Examples to NOT include:

- Generic system libraries unlikely to affect cluster operators (libc, busybox, util-linux, etc.)
- Sub-deps that are already pinned independently in this cluster as their own first-party dep (the skill plans those separately)

If this dep has no meaningful sub-deps, say "none" explicitly — do not omit the section.

If you are running as a sub-dep subagent yourself (see `## Parent context` above), do not recurse: list any sub-sub-deps you find under this section but do not analyze them in this report.

### Per-step analysis

For each step in the upgrade path, produce a subsection with these fields:

- **Step**: `X.Y.Z → X.Y'.Z'`
- **Notable changes**: 3–8 bullets summarizing the major changes shipped in this step — new features, significant improvements, notable bug fixes, meaningful performance changes. This is FYI context for the reader, not impact analysis. Cite the release-notes section for each bullet. Aim for what a reviewer skimming this upgrade would want to know; do not pad with every minor fix. If the release is genuinely small, say so rather than inventing items.
- **Breaking changes**: each breaking change with a citation (release notes URL + section). If none, say "none documented". **Any netpol-required edits identified in the Network policy impact field below must also be listed here** — netpol drift is silent breakage and should be surfaced where readers look first, regardless of whether the project's own release notes called it breaking.
- **Cluster impact**: for each candidate consumer that is a real consumer, describe how this step affects it — specific config to verify, deprecated feature in use, behavior change. If a candidate turned out not to be a real consumer, list it once under "candidates ruled out". If no consumers are affected by this step, say so.
- **Network policy impact**: required edits to `{{COMPONENT_NETPOLS}}` and to consumer netpols. Describe each change in concrete terms — which file, which selector, which ports, which endpoints, what to add/remove/change. Do not write YAML; describe the rule change so the user can apply it in the cluster's CiliumNetworkPolicy conventions. If your method (chart diff + release notes + issue scan + cross-reference) found no netpol-relevant changes for this step, state that explicitly and list the specific signals you checked — silent "no changes" is not acceptable.
- **Repo references**: any of the {{REPO_REFERENCES}} entries that this step resolves, addresses, or is blocked by.
- **Risks**: things that could go wrong, with severity (low / medium / high) and a one-line rationale.

### Prerequisites

List minimum required versions of the following, each as `requires <name> >= <version>`. Omit any that don't apply.

- PostgreSQL
- Redis / Dragonfly
- Kubernetes
- cert-manager
- Operator CRDs the dep depends on
- Any other infrastructure deps (object storage, message queues, etc.)

If the target version introduces a new prerequisite that the current version does not have, call that out explicitly.

### Adaptive split

If the upgrade path has more than 5 steps or includes a major-version jump with extensive release notes, you may dispatch nested research subagents — one per step or per cluster of related steps — and merge their findings. Otherwise handle the whole path yourself.

### Sources

List every URL you consulted with a one-line note on what it confirmed.

## Constraints

- Do not write any files. Research only.
- Do not modify cluster YAML.
- Do not propose a version outside what the policy allows.
- If you cannot confidently determine a step's breaking changes, mark that step "needs manual review" rather than guessing.
- For candidate consumers that turn out not to be real consumers, say so explicitly — do not omit them from the report.
- Use WebFetch / WebSearch for release notes and upstream docs. Use Read / Grep on cluster files when characterizing consumer interactions.
- Do not skip the chart structural diff for any step on the basis that it is "just a patch bump". Patch releases frequently introduce new pods, ports, or outbound calls without flagging them as breaking.
- If you are dispatched as a sub-dep subagent (see `## Parent context`), do not propose a target version different from the one in the prompt — the trajectory is induced by the parent's upgrade path. Do not dispatch further sub-dep subagents; the skill bounds sub-dep research to one level.
````
