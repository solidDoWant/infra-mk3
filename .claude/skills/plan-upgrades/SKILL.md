---
name: plan-upgrades
description: Plan upgrades for a Kubernetes component in this cluster. Use when the user asks to "plan upgrades for X", "what would it take to upgrade Y", "make me an upgrade plan for Z", or similar phrasings. Produces a markdown report; never modifies cluster YAML.
---

# Plan Component Upgrades

Produces a structured markdown report of what it would take to upgrade a component (and its in-scope dependencies) to the latest stable version of each. Writes only the report — does not modify cluster YAML, never opens PRs, never bumps versions automatically.

**Critical rule: Discovery → present scope → user confirms → research → synthesis → write report. Do not dispatch any per-dep research subagents until the user has confirmed scope.**

## Step 1: Discovery

Take the user's target path. Accept anything: a component dir (e.g., `cluster/gitops/security/authentik/`), a single `hr.yaml`, a domain dir (e.g., `cluster/gitops/security/`). Infer scope from what's there.

Scan the target for every version reference:

- HelmRelease: `spec.chart.spec.chart` + `spec.chart.spec.version` (or `chartRef`/sourceRef pinning)
- Image references: `image.repository` + `image.tag` in HelmRelease values, raw Deployments, StatefulSets, DaemonSets, CronJobs, etc.
- Kustomization version overrides
- Operator CRDs with version/image fields (e.g., `RabbitMQCluster.spec.image`, CNPG `Cluster.spec.imageName`)
- Any `appVersion` overrides

Build a **dep table** with these columns:
- Name
- Kind: `chart` | `image` | `local-chart` | `other`
- Current version
- Source (chart repo URL, image registry/repo, or local path)
- File:line

Classify each entry:
- **First-party**: belongs to the project being upgraded (the chart and image of the same software, e.g., authentik chart + authentik server image + authentik outpost image when planning authentik).
- **Platform-coupled**: owned by another component (CNPG, Dragonfly, cert-manager, postgres-operator, etc.). Listed but not planned by default.
- **Local chart**: chart sourced from `cluster/charts/`. Flag as "local, manually maintained, no upstream version to plan".

Discovery is mechanical scanning. Main agent does it directly — no subagent needed.

## Step 2: Present scope, get confirmation

Show the user:

1. The full dep table (first-party / platform-coupled / local-chart sections)
2. Which deps would be planned by default (first-party only)
3. Local charts flagged separately

Ask:
- Confirm or adjust the in-scope set (user may want to add a platform dep, e.g. "also plan postgres")
- Any deps where the target should not be "latest stable" (e.g., "stay on current major")
- Any deps to exclude entirely

**Block on explicit confirmation. Do not dispatch subagents until the user confirms.**

## Step 3: Cluster-impact pre-pass

Before dispatching per-dep research, do a cheap broad grep across `cluster/gitops/` for each in-scope dep. Search for:

- The dep's name (and obvious alternate spellings)
- Chart name
- Image repository substrings
- Service DNS names: `<name>.<namespace>.svc.cluster.local` and common short forms (e.g. `authentik.security`, `authentik-outpost-proxy.security`)
- Well-known ports the dep exposes
- URL fragments specific to the dep (e.g. OIDC `/application/o/`, webhook paths, admin UI paths)

Bias toward false positives. The subagent can discard a non-match by reading the file; it cannot research a file it never saw.

For each in-scope dep, produce a **candidate consumers list**: file paths + ~2 lines of context per hit.

Also grep the target component's own directory for comments/issue/PR markers mentioning the dep (`TODO`, `FIXME`, `HACK`, `github.com/...`, `#<digits>`). These become the **repo references list** for the dep.

Also enumerate every `netpol*.yaml` (and `*netpol.yaml`) file within the target component path itself. These are the netpols this component owns and are the most common edit target during upgrades — new pods or new outbound calls in a new version regularly require netpol changes that release notes don't mention. This becomes the **component netpols list** — file paths only; the subagent reads contents directly.

All three lists go into the subagent prompt at Step 4.

## Step 4: Per-dep research (parallel subagents)

For each in-scope dep, dispatch one subagent. Run them in parallel — emit all the Agent calls in a single message.

### Versioning policy lookup

Before dispatch, check `references/version-policies.md` for the dep. If found, include the policy text verbatim in the subagent prompt.

If not found:

1. Ask the user: stable definition for this dep, where to find release notes, whether minor versions can be skipped.
2. Append a new entry to `references/version-policies.md` using the schema documented at the top of that file.
3. Then dispatch the subagent.

Do not silently guess a policy. A missing entry always results in a user prompt.

### Subagent dispatch

Use the prompt template at `references/subagent-prompt.md`. Fill placeholders with:

- Dep name + current version
- Versioning policy text
- Candidate-consumers list from Step 3
- Repo references list from Step 3
- Component netpols list from Step 3
- Cluster context: kubernetes version, the target component name, one-sentence description of what it does

Subagent type: `Explore` (read-only research is the right shape).

### Adaptive split

If the upgrade path is large (heuristic: >5 version steps, or a major-version jump with extensive release notes), the subagent prompt instructs the subagent to fan out further — one nested subagent per step or per cluster of related steps — and merge results. For typical 1–3 step paths a single subagent handles the whole path itself.

## Step 5: Prerequisite chase

Each subagent's report includes a **Prerequisites** section listing minimum required versions of: postgres, redis/dragonfly, kubernetes, cert-manager, and any operator CRDs the dep depends on.

For each prereq:

1. Determine the cluster's current version of that platform dep (from the discovery pass; if not present in the target, inspect the platform component's `hr.yaml` directly).
2. If the current version satisfies the prereq, note it and move on.
3. If not, dispatch a research subagent for the platform dep — same prompt template, with target version set to the minimum that satisfies the prereq.

Bound to **3 total passes** (initial + 2 prereq-chase rounds). After that, list any remaining unsatisfied prereqs as "manual review needed" in the report rather than chasing further.

## Step 6: Sub-dependency research

Each per-dep subagent's report includes a **Sub-dependencies** section listing meaningful sub-deps bundled with that dep and their version trajectory along its upgrade path. Examples: Rook bundles Ceph; Talos bundles containerd, Linux kernel, runc, and kubelet; a Helm chart can bundle subcharts with their own version streams.

For each (sub-dep, version-trajectory) pair across all subagent reports:

1. Skip the sub-dep if it is already in scope as a first-party or platform-coupled dep in this same plan — its analysis is being produced separately. Note the overlap in the parent's section of the report.
2. Look up the sub-dep in `references/version-policies.md` — same lookup as for direct deps. If missing, ask the user once and append a new entry before dispatching.
3. Dispatch a sub-dep research subagent using the same `references/subagent-prompt.md` template. Substitute `{{PARENT_CONTEXT}}` with a section explaining that this is a sub-dep of the named parent, that the version trajectory is induced (not chosen independently), and that further sub-dep recursion is disallowed.

Sub-dep subagents run in parallel — emit all Agent calls in a single message.

Bound to **one level of nesting**. A sub-dep subagent must not dispatch its own sub-dep subagents. If a sub-dep has meaningful sub-sub-deps, the sub-dep subagent lists them in its own Sub-dependencies section but does not analyze them; the final report surfaces the list under each sub-dep as "further nested deps not analyzed — plan separately if needed".

## Step 7: Synthesis

Main agent, no subagent. Look across all per-dep reports and decide:

- **Strict ordering**: A must complete before B (e.g., postgres operator upgrade before authentik can use new postgres APIs)
- **Parallel groups**: Can ship in one change (e.g., authentik chart and authentik outpost image)
- **Sequential groups**: One at a time but order-independent
- **Cross-cutting risks**: Things that affect multiple deps simultaneously (a kubernetes bump that touches everything, a cert-manager bump affecting every TLS path)

Pull together for the report:
- Combined cluster impact across all in-scope deps (union of the consumer lists, deduped)
- Open questions / things flagged for manual verification
- Local charts flagged in Step 1 (reminder for the user to review separately)

## Step 8: Write the report

Use the skeleton at `references/report-template.md`. Fill placeholders with synthesized data.

Write to `upgrade-plans/{component-slug}-{YYYY-MM-DD}.md` at the repo root.

Component slug: derive from the target path. `cluster/gitops/security/authentik/` → `security-authentik`. For a single `hr.yaml`, use the file's parent path. For a domain dir, use the domain name.

## Step 9: Inform the user

Print:
- The full path to the report
- A 3-bullet summary: count of deps planned, recommended upgrade order at a high level, biggest risks

Do not paste the report contents — it is already on disk.

## Reference Files

- `references/version-policies.md` — Per-dep versioning policy registry. Append-only over time. Each entry: dep name, chart/image identifiers, "stable" definition, release-notes URL, breaking-change indicators, skip-allowed.
- `references/subagent-prompt.md` — Per-dep research subagent prompt template
- `references/report-template.md` — Markdown skeleton for the generated upgrade-plan report
