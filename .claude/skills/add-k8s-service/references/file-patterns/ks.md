# Flux Kustomization Templates

## Single-app with backend

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  namespace: flux-system
  name: &app_name <service>-backend
spec:
  targetNamespace: &namespace <domain>
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app_name
  interval: 5m
  path: /cluster/gitops/<domain>/<service>/backend
  prune: true
  sourceRef:
    kind: GitRepository
    name: infra-mk3
  wait: true
  dependsOn:
    - name: prometheus-crds
    - name: cluster-issuers
    - name: <domain>-namespace-issuer  # needed for postgres/dragonfly mTLS CA
    - name: rook-ceph-cluster          # needed if postgres uses Ceph-backed storage
    - name: cloudnative-pg             # if using postgres
    - name: dragonfly-operator         # if using dragonfly
    - name: rabbitmq-crds              # if using rabbitmq
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  namespace: flux-system
  name: &app_name <service>
spec:
  targetNamespace: <domain>
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app_name
  interval: 5m
  path: /cluster/gitops/<domain>/<service>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: infra-mk3
  wait: true
  dependsOn:
    - name: prometheus-crds
    - name: gateway-crds          # if HTTPRoute is used
    - name: grafana-crds          # if GrafanaDashboard is used
    - name: <service>-backend
```

## Simple app (no backend)

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  namespace: flux-system
  name: &app_name <service>
spec:
  targetNamespace: <domain>
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app_name
  interval: 5m
  path: /cluster/gitops/<domain>/<service>/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: infra-mk3
  wait: true
  dependsOn:
    - name: prometheus-crds
    - name: gateway-crds
```

## Dependency reference

Determine `dependsOn` based on what the service actually uses:

| Condition | Dependency |
|-----------|------------|
| Always | `prometheus-crds` |
| Service exposes HTTPRoute | `gateway-crds` |
| Service has GrafanaDashboard | `grafana-crds` |
| Uses PostgreSQL | `cluster-issuers`, `<namespace>-namespace-issuer`, `cloudnative-pg`, `rook-ceph-cluster` |
| Uses Dragonfly | `dragonfly-operator`, `<namespace>-namespace-issuer` |
| Uses RabbitMQ | `rabbitmq-crds` |
| Uses S3 ObjectBucketClaim | `rook-ceph-cluster` |
| App has a backend KS | name of the backend KS |

The `<namespace>-namespace-issuer` KS name follows the pattern `<domain>-namespace-issuer`. Check whether it already exists for the target domain before adding it as a dependency. If it doesn't exist, create it (see the namespace issuer section in `backends.md`).

## When to use multiple Kustomizations

A single service may need more than two KS resources (not just app + backend):
- **Multiple distinct HelmReleases**: Each chart that benefits from independent reconciliation and rollback gets its own KS
- **Post-install logic**: Any resource that must be created after the Helm chart is ready (e.g., CRD-dependent resources, operator-managed objects) gets its own KS that depends on the main one
- **Components with different readiness**: If one part of the service may fail independently and you don't want it to block others

## Domain kustomization.yaml

After creating the service, add it to the domain's `kustomization.yaml`:

```yaml
resources:
  - ./namespace.yaml
  # ... existing entries ...
  - ./<service>/ks.yaml  # add this
```

If creating a new domain entirely:

`cluster/gitops/<domain>/namespace.yaml`:
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: <domain>
```

`cluster/gitops/<domain>/kustomization.yaml`:
```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml
  - ./<service>/ks.yaml
```

There is no top-level `cluster/gitops/kustomization.yaml` — Flux discovers all domain directories automatically via the root KS in `flux-system`.
