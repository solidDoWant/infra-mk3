# Per-Dependency Version Policies

This file is the registry of versioning policies the `plan-upgrades` skill consults when computing latest-stable targets and upgrade paths. The skill appends new entries here as it encounters new dependencies.

## Schema

Each entry is a level-2 heading naming the dep, followed by these fields:

- **Identifies**: how to recognize this dep in the cluster (chart name(s), image repo(s), both).
- **Stable definition**: the rule for what counts as a stable release. Free-form English — clear enough that a researching subagent can apply it to a list of available versions and pick the latest stable.
- **Release notes**: URL or URL pattern where release notes live. Include placeholder `{version}` if the URL is per-release.
- **Breaking-change indicators**: where to look for breaking changes (a section heading in release notes, a separate `BREAKING-CHANGES.md`, the upgrade guide URL, etc.).
- **Skip-allowed**: whether minor (or major) versions can be skipped, and any constraints on doing so.

When the skill encounters a dep that does not have an entry here, it must ask the user for these fields and append a new entry. Never silently guess a policy.

## Entries

### ceph

- **Identifies**: image `quay.io/ceph/ceph`; also referenced via `rook-ceph-cluster` HelmRelease values and CephCluster CRD `spec.cephVersion.image`.
- **Stable definition**: `<major>.<minor>.<patch>` where `<minor> >= 2`. e.g. `18.2.0` is stable, `18.1.x` is not. The first stable of a major is `<major>.2.0`.
- **Release notes**: https://docs.ceph.com/en/latest/releases/
- **Breaking-change indicators**: each release page has an "Upgrading from previous releases" section; cross-check with the rook-ceph upgrade guide at https://rook.io/docs/rook/latest/Upgrade/ceph-upgrade/ since Rook gates supported Ceph versions.
- **Skip-allowed**: minor versions can be skipped within the same major. Major upgrades must traverse one major at a time per Ceph upgrade docs.

<!-- New entries are appended below this line. Format follows the schema above. -->

### istio

- **Identifies**: Helm charts `base`, `cni`, `istiod`, `ztunnel` from `https://istio-release.storage.googleapis.com/charts` (HelmRepository `istio-charts`). Chart `appVersion` selects the matching `docker.io/istio/*` images (`pilot`, `proxyv2`, `install-cni`, `ztunnel`) — they are not pinned independently in this cluster.
- **Stable definition**: a tag `X.Y.Z` published as a non-prerelease release at https://github.com/istio/istio/releases and present in the istio-charts `index.yaml`. Reject anything with `-rc`, `-beta`, `-alpha`, `-dev`, or `-distroless` suffixes (distroless is a separate image variant, not a version). The latest stable is the highest such tag still inside Istio's [supported releases window](https://istio.io/latest/docs/releases/supported-releases/) (typically N and N-1 minors).
- **Release notes**: per-release announcement at https://istio.io/latest/news/releases/{major}.{minor}.x/announcing-{major}.{minor}/ ; per-patch change notes at https://istio.io/latest/news/releases/{major}.{minor}.x/announcing-{major}.{minor}.{patch}/ ; per-minor upgrade notes at https://istio.io/latest/news/releases/{major}.{minor}.x/announcing-{major}.{minor}/upgrade-notes/ ; GitHub release page at https://github.com/istio/istio/releases/tag/{version}
- **Breaking-change indicators**: each minor announcement has a dedicated "Upgrade Notes" page with "Breaking Changes" and "Action Required" sections. Cross-check the per-minor "What's New" page, the per-patch announcement pages, and any open issues at https://github.com/istio/istio/issues with the `area/ambient`, `area/networking`, or `area/security` labels that mention the target version range. The four charts (`base`, `cni`, `istiod`, `ztunnel`) ship in lockstep — always bump them together to the same `X.Y.Z`.
- **Skip-allowed**: **No minor skipping.** Per https://istio.io/latest/docs/setup/upgrade/ Istio is only tested for upgrades between adjacent minors (`1.26 → 1.27 → 1.28`). Patch versions within a minor may be skipped — when traversing minors, land on the latest patch of each intermediate minor before bumping to the next minor. Ambient-mode upgrades have additional ordering constraints (CNI → ztunnel → istiod → waypoints) that the per-minor upgrade notes call out.

### istio-csr

- **Identifies**: Helm chart `cert-manager-istio-csr` from `https://charts.jetstack.io` (HelmRepository `jetstack-charts`); image `quay.io/jetstack/cert-manager-istio-csr` (selected by chart `appVersion`).
- **Stable definition**: a tag `X.Y.Z` published as a non-prerelease GitHub release at https://github.com/cert-manager/istio-csr/releases AND a non-prerelease chart version at https://charts.jetstack.io/index.yaml. Reject anything with `-alpha`, `-beta`, `-rc` suffixes. Pre-1.0, so each `0.Y.0` minor is effectively a major release per semver — treat minor bumps as potentially breaking.
- **Release notes**: per-release at https://github.com/cert-manager/istio-csr/releases/tag/v{version} ; project README + docs at https://github.com/cert-manager/istio-csr ; cert-manager Istio integration guide at https://cert-manager.io/docs/usage/istio-csr/
- **Breaking-change indicators**: each GitHub release notes page has "Breaking changes" / "Notable changes" subsections. Cross-check the `Chart.yaml` `appVersion` bump against the istio-csr image's compatibility matrix (the project README lists supported Istio minors). Watch the chart's `values.yaml` diff between versions for renamed/removed values keys.
- **Skip-allowed**: **No minor skipping.** Pre-1.0 minor bumps may include breaking changes; traverse minors sequentially (`0.14 → 0.15 → 0.16 ...`). Patch versions within a minor may be skipped.

### cilium

- **Identifies**: Helm chart `cilium` from `https://helm.cilium.io/`; also the bootstrap helmfile in `cluster/bootstrap/helmfile.yaml` (chart version moves in lockstep with the HelmRelease). Cilium images (`quay.io/cilium/cilium`, `quay.io/cilium/operator-generic`, `quay.io/cilium/hubble-relay`, `quay.io/cilium/hubble-ui*`, `quay.io/cilium/cilium-envoy`) are not pinned separately — the chart's `appVersion` selects them.
- **Stable definition**: a tag `vX.Y.Z` published as a non-prerelease release at https://github.com/cilium/cilium/releases (i.e. `prerelease=false`) and that matches strict semver `MAJOR.MINOR.PATCH` with no suffix. Reject anything containing `-rc`, `-pre`, `-alpha`, `-beta`, etc. The latest stable is the highest such tag.
- **Release notes**: per-release at https://github.com/cilium/cilium/releases/tag/v{version} ; upgrade guide at https://docs.cilium.io/en/stable/operations/upgrade/ ; per-minor upgrade notes at https://docs.cilium.io/en/v{major}.{minor}/operations/upgrade/#current-release-required-changes
- **Breaking-change indicators**: each release notes page has "Major Changes" / "Minor Changes" / "Bugfixes" sections; the per-minor upgrade page has a "Current Release Required Changes" / "Upgrade Notes" subsection listing required values changes, deprecations, and removed flags. The "Annotations" / "Helm values" tables on the upgrade page surface renamed Helm keys.
- **Skip-allowed**: **No minor skipping.** The Cilium upgrade guide states the only tested rollback/upgrade path is between consecutive minor releases (`1.17 → 1.18 → 1.19`). Patch versions within a minor may be skipped — when traversing minors, land on the latest patch of each intermediate minor before bumping to the next minor.

### rook-ceph

- **Identifies**: Helm charts `rook-ceph` (operator) and `rook-ceph-cluster` (cluster/CRs) from `https://charts.rook.io/release`; also the operator image `rook/ceph` (referenced indirectly via the chart). The two charts are always version-locked.
- **Stable definition**: A Rook release `vX.Y.Z` is stable if **all** of: (a) it is published as a non-prerelease GitHub release at https://github.com/rook/rook/releases AND a non-prerelease chart version at https://charts.rook.io/release/index.yaml; (b) the chart's default `cephClusterSpec.cephVersion.image` resolves to a Ceph version that satisfies the **ceph** entry's stable definition above (i.e., Ceph `<major>.<minor>.<patch>` with `minor >= 2`). Reject any Rook version whose default Ceph image is not itself stable. Prefer the highest patch on the highest minor that meets both conditions.
- **Release notes**: per-release at https://github.com/rook/rook/releases/tag/v{version} ; upgrade guide at https://rook.io/docs/rook/latest/Upgrade/rook-upgrade/ ; Ceph upgrade compatibility at https://rook.io/docs/rook/latest/Upgrade/ceph-upgrade/
- **Breaking-change indicators**: each GitHub release notes page has a "Breaking Changes" section; the dedicated upgrade-guide page is the authoritative source for required ordering and pre-upgrade checks. Minimum supported Ceph version is stated per Rook minor in the release notes.
- **Skip-allowed**: **No minor skipping.** Rook supports upgrades between consecutive minors only (`1.16 → 1.17 → 1.18 → 1.19`). Patch versions within a minor may be skipped (e.g., `1.16.0 → 1.16.4` is fine). When traversing minors, take the latest patch of each intermediate minor as the landing version before moving to the next minor.

### kubernetes

- **Identifies**: Talos `kubernetesVersion` field in `talos/talconfig.yaml`. Also drives any kubectl image/binary pin (`registry.k8s.io/kubectl:vX.Y.Z`, `dl.k8s.io/release/vX.Y.Z/...`) — but those are tracked by the separate **kubectl** entry below.
- **Stable definition**: latest non-prerelease patch (`vX.Y.Z`, no `-rc`/`-alpha`/`-beta` suffix) on the highest minor that is **both** (a) in the Kubernetes "Supported Versions" window at https://kubernetes.io/releases/ AND (b) explicitly listed in the support matrix of the cluster's current Talos minor at https://docs.siderolabs.com/talos/v{talos_minor}/getting-started/support-matrix. Reject any minor not in both sets.
- **Release notes**: per-minor CHANGELOG at https://github.com/kubernetes/kubernetes/blob/release-{major}.{minor}/CHANGELOG/CHANGELOG-{major}.{minor}.md ; per-minor highlights at https://kubernetes.io/blog/ (search "Kubernetes v{major}.{minor}: ..."); deprecation guide at https://kubernetes.io/docs/reference/using-api/deprecation-guide/
- **Breaking-change indicators**: each minor's CHANGELOG has "Urgent Upgrade Notes (No, really, you MUST read this before you upgrade)" and "Deprecation" / "Removal" sections; cross-check the Talos release notes for the corresponding Talos minor for any host-side feature-gate or kubelet-flag changes; verify every feature gate set in `talconfig.yaml` (currently `DynamicResourceAllocation`, `DRAAdminAccess`, `DRAPartitionableDevices`, `UserNamespacesPodSecurityStandards`, `ImageVolume`) against the target minor's KEP graduation table — gates that have **graduated to GA and been removed** must be deleted from talconfig, gates that are removed-and-not-graduated must be deleted too. Also check the API removal list against any CRDs / built-in resources the cluster uses.
- **Skip-allowed**: **No minor skipping.** Kubernetes supports control-plane upgrades only between consecutive minors (`n → n+1`); kubelet skew tolerated is `n-3..n`. Patches within a minor may be skipped (always land on the latest patch of each minor when traversing).

### talos

- **Identifies**: Talos `talosVersion` field in `talos/talconfig.yaml`; installer images `ghcr.io/siderolabs/installer:vX.Y.Z`; image-factory URLs of the form `factory.talos.dev/{...}/vX.Y.Z`.
- **Stable definition**: latest non-prerelease patch (`vX.Y.Z`, no `-alpha`/`-beta`/`-rc` suffix) on the **specified minor** whose release notes confirm support for the target Kubernetes minor in the support matrix. Reject any patch published before the target Kubernetes minor's GA date (such patches predate the support claim).
- **Release notes**: per-release at https://github.com/siderolabs/talos/releases/tag/v{version} ; per-minor upgrade guide at https://www.talos.dev/v{major}.{minor}/talos-guides/upgrading-talos/ ; support matrix at https://docs.siderolabs.com/talos/v{major}.{minor}/getting-started/support-matrix
- **Breaking-change indicators**: each release page has a "Component Updates" and (when present) "Breaking Changes" / "Upgrade Notes" section; the per-minor upgrade guide is authoritative for required pre-upgrade steps; the support matrix is authoritative for which Kubernetes minors a given Talos minor supports.
- **Skip-allowed**: patches within a minor may be skipped (always land on the latest patch). Minor skipping (e.g. `1.11 → 1.13`) is **not supported** — Talos must traverse minors sequentially. (Out of scope for plans that explicitly constrain Talos to its current minor.)

### snapshot-controller (Piraeus chart)

- **Identifies**: Helm chart `snapshot-controller` from HelmRepository `piraeus-charts` (https://piraeus.io/helm-charts/). The chart is a community packaging of the upstream `kubernetes-csi/external-snapshotter` snapshot-controller. The controller image (`registry.k8s.io/sig-storage/snapshot-controller`) is selected by the chart's `appVersion` and not pinned independently in this cluster. Note: the CRDs in `cluster/gitops/storage/volume-snapshot/crds/` are sourced separately from `github.com/kubernetes-csi/external-snapshotter//client/config/crd` and tracked independently.
- **Stable definition**: a chart version `X.Y.Z` published in the piraeus-charts `index.yaml` (https://piraeus.io/helm-charts/index.yaml) with no `-rc`, `-alpha`, `-beta`, `-pre`, or `-dev` suffix. Cross-check with non-prerelease GitHub releases at https://github.com/piraeusdatastore/helm-charts/releases. The latest stable is the highest such version.
- **Release notes**: chart release notes at https://github.com/piraeusdatastore/helm-charts/releases (search for `snapshot-controller-{version}` tags); commits affecting the chart at https://github.com/piraeusdatastore/helm-charts/commits/main/charts/snapshot-controller ; upstream controller release notes at https://github.com/kubernetes-csi/external-snapshotter/releases (matched by the chart's `appVersion`); upstream README at https://github.com/kubernetes-csi/external-snapshotter#readme
- **Breaking-change indicators**: GitHub release pages for the chart rarely flag breaking changes explicitly — diff `charts/snapshot-controller/values.yaml` and `charts/snapshot-controller/templates/` between the from/to tags for renamed values keys, removed knobs, or new required fields. Cross-check the upstream `external-snapshotter` release for the chart's target `appVersion` — its "Action Required" / "Urgent Upgrade Notes" sections call out controller-side behavior changes, new feature gates, and CRD version requirements. Verify the chart's bundled CRD requirement against the separately-managed `crds/kustomization.yaml` pin.
- **Skip-allowed**: minor (and major) versions may be skipped. The chart is a thin wrapper around upstream and chart-major bumps are infrequent; pick the target patch directly. (Upstream `external-snapshotter` does not guarantee skip support — verify the controller `appVersion` jump is supported per its release notes when crossing majors.)

### kubectl

- **Identifies**: Image refs `registry.k8s.io/kubectl:vX.Y.Z`; binary download URLs `https://dl.k8s.io/release/vX.Y.Z/bin/...` in scripts or container images that pull kubectl at startup.
- **Stable definition**: latest non-prerelease patch (`vX.Y.Z`) on the **same minor as the cluster's `kubernetesVersion`** in `talos/talconfig.yaml`. Patch may run ahead of or behind the server patch within the same minor. Cross-minor skew is limited to ±1 minor per upstream policy at https://kubernetes.io/releases/version-skew-policy/#kubectl ; prefer matching the cluster minor exactly.
- **Release notes**: bundled inside the Kubernetes per-minor CHANGELOG (search the file for `### kubectl` sections) at https://github.com/kubernetes/kubernetes/blob/release-{major}.{minor}/CHANGELOG/CHANGELOG-{major}.{minor}.md
- **Breaking-change indicators**: kubectl flag/output deprecations are called out in the CHANGELOG's "Deprecation" section under kubectl; also check `kubectl ... --help` diffs across versions when a flag is suspected of being renamed.
- **Skip-allowed**: patches may be skipped freely. The minor must match (or be one off from) the chosen cluster k8s minor — bump kubectl in lockstep with each k8s minor upgrade.
