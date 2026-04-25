# Adding New Flux Helm Sources

HelmRepository resources live in `cluster/gitops/flux-system/flux/sources/helm/`. Each gets its own file named `<chart-name>-charts.yaml`.

Before adding a new source, check the existing files in that directory — the chart you need may already be registered.

## OCI registry (most modern charts)

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/source.toolkit.fluxcd.io/helmrepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: <name>-charts
  namespace: flux-system   # Needed for https://kubesearch.dev/ indexing
spec:
  url: oci://ghcr.io/<org>/helm
  type: oci
```

## HTTP/HTTPS Helm repository

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/source.toolkit.fluxcd.io/helmrepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: <name>-charts
  namespace: flux-system
spec:
  url: https://charts.example.com
```

After creating the file, reference the source in the HelmRelease:
```yaml
sourceRef:
  kind: HelmRepository
  namespace: flux-system
  name: <name>-charts
```

New files in `cluster/gitops/flux-system/flux/sources/helm/` are picked up automatically — the `flux-sources` Kustomization points at the parent `sources/` directory and Flux discovers all YAML files recursively. No manual registration required.
