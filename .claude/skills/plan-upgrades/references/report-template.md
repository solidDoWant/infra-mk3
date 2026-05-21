# Upgrade Plan Report Skeleton

Used by the `plan-upgrades` skill at Step 8 to render the final report. Substitute `{{...}}` placeholders with synthesized data; drop sections that are genuinely empty (e.g., omit "Platform prerequisites pulled into scope" if no prereqs forced platform deps in).

````
# Upgrade plan: {{COMPONENT_NAME}}

Generated: {{ISO_DATE}}
Target path: `{{TARGET_PATH}}`

## Recommended upgrade order

{{ORDER_SUMMARY}}

A high-level ordered list of how to sequence the upgrades. Each entry references a per-dep section below. Note explicitly which steps can ship in one change vs which require strict sequencing.

## Dependencies in scope

| Dep | Kind | Current | Target | Steps |
|-----|------|---------|--------|-------|
| ... | ...  | ...     | ...    | ...   |

## Platform prerequisites pulled into scope

(Omit this section if empty.)

| Platform dep | Current | Required by | Required minimum | Plan section |
|--------------|---------|-------------|------------------|--------------|
| ...          | ...     | ...         | ...              | ...          |

## Network policy changes summary

(Omit this section if no netpol edits are required across the whole plan.)

Consolidated checklist of every netpol edit needed across all in-scope deps, their analyzed sub-deps, and steps, deduped. Each entry cites the per-step section where it was identified so the user can read the full rationale.

- `<file path>` — `<change description>` — required by `<dep>` step `<X.Y.Z → X.Y'.Z'>`
- ...

## Per-dep details

### {{DEP_NAME}}

**Current → Target**: `{{CURRENT}}` → `{{TARGET}}`

**Reasoning**: {{POLICY_REASONING}}

**Upgrade path**:

1. `{{STEP_1}}`
2. `{{STEP_2}}`

#### Step `X.Y.Z → X.Y'.Z'`

**Notable changes**
- ...

**Breaking changes**
- ...

**Cluster impact**
- ...
- _Candidates ruled out_: ...

**Network policy impact**
- `<file path>` — `<change description>`
- ...

**Repo references**
- ...

**Risks**
- low / medium / high — ...

(Repeat the step subsection per step.)

#### Sub-dependencies

(Omit this section if no sub-deps were analyzed for this dep.)

##### Sub-dep: `<name>` (trajectory: `<from-version> → <to-version>`)

**Upgrade path**:

1. `<step 1>`
2. `<step 2>`

###### Step `X.Y.Z → X.Y'.Z'`

**Notable changes**
- ...

**Breaking changes**
- ...

**Cluster impact**
- ...

**Network policy impact**
- ...

**Repo references**
- ...

**Risks**
- low / medium / high — ...

(Repeat the step subsection per sub-dep step. Repeat the sub-dep subsection per sub-dep.)

##### Further nested deps surfaced but not analyzed

(Omit if empty.)

- `<sub-sub-dep>` — surfaced by `<sub-dep>` analysis; plan separately if needed.

(Repeat the dep section per dep.)

## Cross-cutting risks

Risks that span multiple deps or affect cluster-wide behavior (e.g. a Kubernetes bump that touches every workload, a cert-manager bump affecting every TLS path).

- ...

## Manual review needed

Items the skill could not resolve and that need human attention. Includes:

- Steps marked "needs manual review" by a research subagent
- Unsatisfied prerequisites remaining after the prereq-chase bound
- Any policy ambiguity that the user should resolve before applying

- ...

## Local charts in this component (not planned by skill)

(Omit this section if empty.)

- `cluster/charts/<name>` — referenced by `<file>`. Manually maintained; review separately.

## Sources

Aggregated source URLs from per-dep research, deduped.

- ...
````
