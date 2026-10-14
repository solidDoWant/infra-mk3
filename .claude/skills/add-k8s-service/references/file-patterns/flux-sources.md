# Flux Chart Sources

## Official OCI charts (default)

Each HelmRelease gets its own `OCIRepository`, named after the HelmRelease and placed in the same `hr.yaml` directly above it. The chart version lives in `ref.tag`; Renovate bumps it there.

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: <service>
spec:
  interval: 1h
  url: oci://ghcr.io/<org>/charts/<chart>
  ref:
    tag: 1.2.3
  verify: # only when the chart is signed; see "Signature verification"
    provider: cosign
    matchOIDCIdentity:
      - issuer: ^https://token\.actions\.githubusercontent\.com$
        subject: ^https://github\.com/<org>/<repo>/\.github/workflows/<workflow>\.yaml@refs/.+$
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <service>
spec:
  chartRef:
    kind: OCIRepository
    name: <service>
```

Don't set `layerSelector`: a Flux meta-patch (`cluster/gitops/flux-system/flux/cluster/ks.yaml`) adds the Helm chart layer selector to every OCIRepository. An OCI artifact that is not a Helm chart must opt out with the label `patches.flux.home.arpa/ocirepository.helm-chart: "false"`. Keep `interval`: the CRD requires it, so leaving it to a patch would fail schema validation.

Leave `metadata.namespace` and `chartRef.namespace` unset: both resolve to the Kustomization's `targetNamespace`. kubesearch.dev also matches an OCIRepository to its HelmRelease by name when neither sets a namespace. (A HelmRepository is different; see below.)

Verify the tag exists and is a chart before using it — some registries drop the `v` prefix the HTTPS repo uses (e.g. Rook):
```bash
crane manifest <registry>/<path>/<chart>:<tag> | jq -r .config.mediaType   # application/vnd.cncf.helm.config.v1+json
```

## Signature verification

Add `spec.verify` to every OCIRepository whose chart is signed. Check before writing the OCIRepository:

```bash
# Any signature at all? (checks both cosign v2 .sig tags and v3 bundles via OCI referrers)
cosign verify <registry>/<path>/<chart>:<tag> \
  --certificate-identity-regexp '.*' --certificate-oidc-issuer-regexp '.*' >/dev/null && echo signed
# Who signed it: read the cert from the v3 bundle (or the .sig layer's dev.sigstore.cosign/certificate annotation)
cosign tree <registry>/<path>/<chart>:<tag>   # shows the referrer holding the bundle
```

The signing certificate's SAN is the `subject` and its OIDC issuer extension is the `issuer`. Before committing, confirm the exact regexes pass, and that a wrong subject fails:
```bash
cosign verify <ref> --certificate-oidc-issuer-regexp '<issuer>' --certificate-identity-regexp '<subject>'
```

Rules for `matchOIDCIdentity` (both fields are Go regular expressions):
- Escape every literal `.` (`github\.com`, `\.yaml`). An unescaped `.` matches any character.
- Anchor both ends, and pin the subject to the repo **and** workflow file. End GitHub subjects with `@refs/.+$` so tags and branches both match. Never end with a bare `.*`: `charts-mirror.*$` also matches a `charts-mirror-evil` repo.
- If the subject is a shared reusable workflow (e.g. `action-stars/helm-workflows`, used by fluent), it does not identify the upstream repo. Add it anyway, but say so in a comment above `verify`.
- Static-key signatures (`cosign verify --key`) only work if signed with SHA-256: source-controller hardcodes SHA-256 for public keys. cert-manager signs with SHA-512, so its chart can't be verified.
- No signature: omit `verify`. Helm PGP provenance (`.prov`) is not supported by OCIRepository.

If upstream later changes its signing workflow, verification fails and the OCIRepository goes not-Ready. That shows up in the Renovate bump PR's rollout; update the `subject` there.

## home-operations charts-mirror (no official OCI chart)

If upstream publishes no OCI chart, **always** check https://github.com/home-operations/charts-mirror (the `apps/` directory lists mirrored charts) before falling back to a HelmRepository:
```bash
crane ls ghcr.io/home-operations/charts-mirror/<chart>
crane manifest ghcr.io/home-operations/charts-mirror/<chart>:<version> | jq -r .config.mediaType
```
Mirror tags have no `v` prefix even when upstream uses one (e.g. `k8s-gpu-dra-driver` `v1.0.1` → `1.0.1`).

Use the same OCIRepository pattern with `url: oci://ghcr.io/home-operations/charts-mirror/<chart>`. Every mirrored OCIRepository **must** have a comment above `url` linking the upstream OCI tracking issue (listed in https://github.com/home-operations/charts-mirror/issues/8; search the upstream repo if the chart isn't listed, and fall back to linking #8). Mirror charts are always signed, so it also needs cosign verification of the mirror's signing identity:
```yaml
  # Stop-gap mirror, pruned 6 months after upstream publishes an OCI chart.
  # Switch to the official chart once <upstream issue URL> lands.
  url: oci://ghcr.io/home-operations/charts-mirror/<chart>
  ref:
    tag: 1.2.3
  verify:
    provider: cosign
    matchOIDCIdentity:
      - issuer: ^https://token\.actions\.githubusercontent\.com$
        subject: ^https://github\.com/home-operations/charts-mirror/\.github/workflows/app-builder\.yaml@refs/.+$
```

The mirror is a stop-gap: it prunes a chart 6 months after upstream starts publishing an official OCI chart. Renovate adds a reminder to mirror-chart PRs; switch the `url` to the official chart once it exists. The mirror does not cover tightly coupled chart families when only some members are mirrored (e.g. teleport-operator is absent, so all teleport charts stay on one HelmRepository).

## HTTPS Helm repository (only when neither an official nor a mirrored OCI chart exists)

HelmRepository resources live in `cluster/gitops/flux-system/flux/sources/helm/`, one file per repo named `<name>-charts.yaml`. Check that directory first — the repo may already be registered.

```yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: <name>-charts
  namespace: flux-system # Needed for https://kubesearch.dev/ indexing
spec:
  url: https://charts.example.com
```

`namespace: flux-system` is required on both the HelmRepository and the HelmRelease `sourceRef`. The HelmRelease lives in another namespace, and kubesearch.dev only links a HelmRelease to a HelmRepository when the two namespaces match exactly.

Reference it from the HelmRelease:
```yaml
  chart:
    spec:
      chart: <chart>
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        namespace: flux-system
        name: <name>-charts
      version: 1.2.3
```

New files in `sources/helm/` are picked up automatically by the `flux-sources` Kustomization.
