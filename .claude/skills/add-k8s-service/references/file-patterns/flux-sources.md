# Flux Chart Sources

## OCI charts (default)

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

## HTTPS Helm repository (only when no OCI chart is published)

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
