# Flux Chart Sources

## Official OCI charts (default)

Each HelmRelease gets its own `OCIRepository`, named after the HelmRelease and placed in the same `hr.yaml` directly above it. The chart version lives in `ref.tag`; Renovate bumps it there.

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: <service>
spec:
  interval: 1h
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  url: oci://ghcr.io/<org>/charts/<chart>
  ref:
    tag: 1.2.3
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

Verify the tag exists and is a chart before using it — some registries drop the `v` prefix the HTTPS repo uses (e.g. Rook):
```bash
crane manifest <registry>/<path>/<chart>:<tag> | jq -r .config.mediaType   # application/vnd.cncf.helm.config.v1+json
```

## home-operations charts-mirror (no official OCI chart)

If upstream publishes no OCI chart, **always** check https://github.com/home-operations/charts-mirror (the `apps/` directory lists mirrored charts) before falling back to a HelmRepository:
```bash
crane ls ghcr.io/home-operations/charts-mirror/<chart>
crane manifest ghcr.io/home-operations/charts-mirror/<chart>:<version> | jq -r .config.mediaType
```
Mirror tags have no `v` prefix even when upstream uses one (e.g. `k8s-gpu-dra-driver` `v1.0.1` → `1.0.1`).

Use the same OCIRepository pattern with `url: oci://ghcr.io/home-operations/charts-mirror/<chart>`, plus cosign verification of the mirror's signing identity:
```yaml
  verify:
    provider: cosign
    matchOIDCIdentity:
      - issuer: ^https://token.actions.githubusercontent.com$
        subject: ^https://github.com/home-operations/charts-mirror.*$
```

The mirror is a stop-gap: it prunes a chart 6 months after upstream starts publishing an official OCI chart. Renovate adds a reminder to mirror-chart PRs; switch the `url` to the official chart once it exists. The mirror does not cover tightly coupled chart families when only some members are mirrored (e.g. teleport-operator is absent, so all teleport charts stay on one HelmRepository).

## HTTPS Helm repository (only when neither an official nor a mirrored OCI chart exists)

HelmRepository resources live in `cluster/gitops/flux-system/flux/sources/helm/`, one file per repo named `<name>-charts.yaml`. Check that directory first — the repo may already be registered.

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/source.toolkit.fluxcd.io/helmrepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: <name>-charts
  namespace: flux-system # Needed for https://kubesearch.dev/ indexing
spec:
  url: https://charts.example.com
```

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
