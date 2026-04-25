# Backend — PostgreSQL (CloudNative-PG)

**Prefer PostgreSQL over local/embedded databases** (SQLite, embedded BoltDB, etc.) whenever the application supports it. PostgreSQL provides: automated backups, HA, mTLS, Teleport access, and consistent operational patterns across the cluster.

Deploy `auth` first (creates mTLS client certs), then `cluster` (depends on auth via `dependsOn`).

PostgreSQL clusters run with `instances: 2` by default (the chart default) — this provides one primary and one standby for HA. The custom chart handles storage class selection (OpenEBS ZFS with dedicated tuned storage class) since CNPG provides its own replication.

## backend/postgres/auth/hr.yaml

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <service>-postgres-auth
spec:
  interval: 5m
  chart:
    spec:
      chart: ./cluster/charts/postgres/auth
      sourceRef:
        kind: GitRepository
        namespace: flux-system
        name: infra-mk3
  values:
    serviceName: <service>
    certificates:
      ca:
        subject:
          countries: [US]
          provinces: ["${SECRET_STATE}"]
          organizations: [infra-mk3]
    teleportDomainName: teleport.${SECRET_PUBLIC_DOMAIN_NAME}
    users:
      <service>:
        username: <service>
        disableReloading: true
```

## backend/postgres/17/hr.yaml

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <service>-postgres-17
spec:
  interval: 5m
  chart:
    spec:
      chart: ./cluster/charts/postgres/cluster
      reconcileStrategy: Revision
      sourceRef:
        kind: GitRepository
        namespace: flux-system
        name: infra-mk3
  dependsOn:
    - name: <service>-postgres-auth
  values:
    clusterName: <service>
    certificates:
      serving:
        issuerRef:
          name: <namespace>-intermediary-ca
        subject:
          countries: [US]
          provinces: ["${SECRET_STATE}"]
          organizations: [infra-mk3]
        privateKey:
          # Use ECDSA for .NET/C# apps — Ed25519 is not supported by the .NET runtime
          # Use Ed25519 for everything else (better performance, smaller keys)
          algorithm: Ed25519   # or ECDSA with size: 384, encoding: PKCS8 for .NET
          encoding: PKCS8
          rotationPolicy: Always
    bucket:
      endpoint: https://s3.${SECRET_PUBLIC_DOMAIN_NAME}
    netpol:
      applicationAccess:
        selectors:
          # Add one entry per set of pods that need database access.
          # Scope labels tightly to the specific controller/instance.
          - matchLabels:
              app.kubernetes.io/name: <service>
              app.kubernetes.io/controller: <service>
              app.kubernetes.io/instance: <service>
```

The cluster creates services:
- `<service>-postgres-17-rw.<namespace>.svc.cluster.local:5432` — read-write (primary)
- `<service>-postgres-17-r.<namespace>.svc.cluster.local:5432` — read-only (replicas)

The `auth` chart creates a secret named `<service>-postgres-<username>` with keys `tls.crt` and `tls.key`.

---

## Namespace Issuer (required for postgres and dragonfly mTLS)

Check whether `cluster/gitops/<domain>/issuers/` already exists before creating. If it doesn't, create:

`cluster/gitops/<domain>/issuers/ks.yaml`:
```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  namespace: flux-system
  name: &app_name <domain>-namespace-issuer
spec:
  targetNamespace: &namespace <domain>
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app_name
  interval: 5m
  path: /cluster/gitops/<domain>/issuers/namespace
  postBuild:
    substitute:
      NAMESPACE: *namespace
      CERT_ALGORITHM: Ed25519    # or ECDSA if the namespace needs .NET-compatible certs
  prune: true
  sourceRef:
    kind: GitRepository
    name: infra-mk3
  wait: true
  dependsOn:
    - name: cluster-issuers
```

`cluster/gitops/<domain>/issuers/namespace/kustomization.yaml`:
```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
components:
  - ../../../../components/issuers/namespace
```

Add `./issuers/ks.yaml` to the domain's `kustomization.yaml`.
