# Backend — PostgreSQL (CloudNative-PG)

**Prefer PostgreSQL over local/embedded databases** (SQLite, embedded BoltDB, etc.) whenever the application supports it. PostgreSQL provides: automated backups, HA, mTLS, Teleport access, and consistent operational patterns across the cluster.

A single merged chart — `cluster/charts/postgres/cluster` — provisions the CNPG cluster, the client-auth PKI (CA, per-user client certs, CertificateRequestPolicies), the serving cert, the WAL backup bucket, network policy, Teleport registration, and monitoring. There is no longer a separate `auth` chart or a `dependsOn` between two releases — author one HelmRelease at `backend/postgres/hr.yaml`.

PostgreSQL clusters run with `instances: 2` by default (the chart default) — this provides one primary and one standby for HA. The chart handles storage class selection (OpenEBS ZFS with a dedicated tuned storage class) since CNPG provides its own replication.

## backend/postgres/hr.yaml

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <service>-postgres
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
  values:
    clusterName: <service>
    teleportDomainName: teleport.${SECRET_PUBLIC_DOMAIN_NAME}
    certificates:
      client:
        ca:
          subject: &subject
            countries: [US]
            provinces: ["${SECRET_STATE}"]
            organizations: [infra-mk3]
      serving:
        issuerRef:
          name: <namespace>-intermediary-ca
        subject: *subject
        # privateKey defaults to Ed25519 (chart default) — preferred for its
        # performance and smaller keys. Override ONLY for .NET/C# apps, whose
        # runtime can't use Ed25519 certs — use ECDSA there instead:
        #   privateKey:
        #     algorithm: ECDSA
        #     size: 384
        #     encoding: PKCS8
        #     rotationPolicy: Always
        # IMPORTANT: if the app reaches postgres through the Envoy mTLS sidecar
        # (references/envoy-sidecar-pg.yaml), an Ed25519 serving cert REQUIRES
        # `ed25519` in that sidecar's tls_params.signature_algorithms — Envoy's
        # BoringSSL won't advertise it by default, and the handshake fails with
        # "no suitable signature algorithm". See that file's comment for detail.
    users:
      <service>:
        username: <service>
        disableReloading: true   # required for Envoy SDS cert hot-reload; see operators.md
    bucket:
      endpoint: https://s3.${SECRET_PUBLIC_DOMAIN_NAME}
    netpol:
      applicationAccess:
        # Use `selector` for a single set of pods, or `selectors` (a list) when
        # multiple distinct workloads need database access. Scope labels tightly
        # to the specific controller/instance.
        selector:
          matchLabels:
            app.kubernetes.io/name: <service>
            app.kubernetes.io/controller: <service>
            app.kubernetes.io/instance: <service>
```

The cluster creates services (named after the cluster resource, `<service>-postgres`):
- `<service>-postgres-rw.<namespace>.svc.cluster.local:5432` — read-write (primary)
- `<service>-postgres-ro.<namespace>.svc.cluster.local:5432` — read-only (replicas)
- `<service>-postgres-r.<namespace>.svc.cluster.local:5432` — any instance (primary or replica)

For each entry under `users`, the chart creates a client-cert secret named `<service>-postgres-<username>-user` with keys `tls.crt`, `tls.key`, and `ca.crt`. (E.g. `users.<service>.username: <service>` → secret `<service>-postgres-<service>-user`.) The `streaming-replica` and `pooler` users are defined by the chart defaults — only add your application's user(s).

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
