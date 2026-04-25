# HelmRelease — app-template

Use the latest app-template by default. Always pin the chart version and all image tags.

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <service>
spec:
  interval: 5m
  chart:
    spec:
      chart: app-template
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        namespace: flux-system
        name: bjw-s-charts
      version: 4.6.2
  values:
    controllers:
      <service>:
        replicas: 2                    # Required if using PDB
        podDisruptionBudget:           # Inline PDB — preferred over standalone pdb.yaml, but only use if PDB >= 2
          minAvailable: 1
        containers:
          app:
            image:
              repository: ghcr.io/home-operations/<service>   # Prefer home-operations if available
              tag: 1.2.3                                       # Always pin to a specific version
            env:
              EXAMPLE_SECRET:
                secretKeyRef:
                  name: <service>-credentials
                  key: SECRET_KEY
              # No TZ env var needed — k8tz injects it automatically
            ports:
              - name: web
                containerPort: &web_port <port>
            probes:
              readiness: &probe
                enabled: true
                type: HTTP
                path: /health      # Adjust to actual health endpoint; omit path for TCP probes
              liveness: *probe
            securityContext: &security_ctx
              readOnlyRootFilesystem: true
              allowPrivilegeEscalation: false
              capabilities:
                drop: [ALL]
        pod:
          labels:
            # Add custom netpol labels here if other services need to select this pod
            # e.g.: endpoints.netpols.home.arpa/some-role: "true"
    defaultPodOptions:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000      # Use the UID defined by the base image, if any
        runAsGroup: 1000     # Use the GID defined by the base image, if any
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
      dnsConfig:
        options:
          - name: ndots
            value: "1"
    resources:
      # Requests are optional.
      requests:
        cpu: 10m
        memory: 128Mi
      limits:
        # Always set memory limit = memory request to avoid OOM surprises.
        # CPU limits are intentionally omitted — unbounded CPU allows bursting.
        memory: 128Mi
    # Inline ConfigMap — define config files directly in the HelmRelease.
    # app-template creates and manages the ConfigMap; reference it in persistence via `identifier:`.
    # Flux variable substitution works here, so ${SECRET_VARS} can be used.
    configMaps:
      config:
        data:
          config.yaml: |
            some_setting: value
    persistence:
      config:
        type: configMap
        identifier: config    # Matches the key under configMaps: above
        advancedMounts:
          <service>:
            app:
              - path: /etc/<service>/config.yaml
                subPath: config.yaml
                readOnly: true
      # Example - not always needed
      tmp:
        type: emptyDir
        medium: Memory
        sizeLimit: 50Mi
        advancedMounts:
          <service>:
            app:
              - path: /tmp
    service:
      <service>:
        controller: <service>
        ports:
          web:
            port: *web_port
            primary: true
    # Inline HTTPRoute (preferred for simple cases)
    route:
      <service>:
        hostnames:
          - <service>.${SECRET_PUBLIC_DOMAIN_NAME}
        parentRefs:
          - name: internal-gateway
            namespace: networking
        rules:
          - backendRefs:
              - identifier: <service>
                port: *web_port
          # Include the outpost rule ONLY when using Authentik proxy forward-auth (not OIDC)
          # - backendRefs:
          #     - name: authentik-outpost-proxy
          #       namespace: security
          #       port: 80
          #   matches:
          #     - path:
          #         type: PathPrefix
          #         value: /outpost.goauthentik.io
```

## Metrics via app-template serviceMonitor

App-template supports inline serviceMonitor config. Use this instead of a standalone VMServiceScrape when the app is deployed via app-template:

```yaml
    serviceMonitor:
      <service>:
        endpoints:
          - port: metrics
            interval: 1m
```

If you need VM-specific features (e.g., `discoveryRole: service` to avoid duplicate metrics from HA deployments), use a standalone `VMServiceScrape` instead — see `monitoring.md`.

## PostgreSQL mTLS volumes (native TLS support)

When the application supports TLS client certs natively, mount all certs under `/etc/<app>/certs/<backend>/` — the root CA goes inside the same backend directory to avoid conflicts. If the service connects to multiple postgres instances, add an extra `/<instance-name>/` level (e.g., `/etc/<service>/certs/postgres/primary/`).

```yaml
    persistence:
      # Mount the postgres client cert and root CA together under the backend directory
      <service>-postgres-user-cert:
        type: secret
        name: <service>-postgres-<user>    # Created by the postgres/auth chart
        defaultMode: 0440
        items:
          - key: tls.crt
            path: tls.crt
          - key: tls.key
            path: tls.key
        advancedMounts:
          <service>:
            app:
              - path: /etc/<service>/certs/postgres
      # Mount the cluster root CA alongside the client cert
      root-ca:
        type: secret
        name: root-ca-pub-cert
        defaultMode: 0444
        items:
          - key: ca.crt
            path: ca.crt
        advancedMounts:
          <service>:
            app:
              - path: /etc/<service>/certs/postgres/ca.crt
                subPath: ca.crt
```

## PostgreSQL connection string

The connection string format varies significantly by language and library. Common forms:

**.NET (Npgsql)**:
```
Server=<service>-postgres-17-rw.<namespace>.svc.cluster.local;Database=<db>;Username=<user>;SSLMode=VerifyCA;RootCertificate=/etc/<service>/certs/postgres/ca.crt;SSLCertificate=/etc/<service>/certs/postgres/tls.crt;SSLKey=/etc/<service>/certs/postgres/tls.key
```

**Go / libpq URL**:
```
postgresql://<user>@<service>-postgres-17-rw.<namespace>.svc.cluster.local/<db>?sslmode=verify-ca&sslrootcert=/etc/<service>/certs/postgres/ca.crt&sslcert=/etc/<service>/certs/postgres/tls.crt&sslkey=/etc/<service>/certs/postgres/tls.key
```

**libpq environment variables**:
```yaml
PGHOST: <service>-postgres-17-rw.<namespace>.svc.cluster.local
PGDATABASE: <db>
PGUSER: <user>
PGSSLMODE: verify-ca
PGSSLROOTCERT: /etc/<service>/certs/postgres/ca.crt
PGSSLCERT: /etc/<service>/certs/postgres/tls.crt
PGSSLKEY: /etc/<service>/certs/postgres/tls.key
```

Research the app's documentation to determine the right form.

## NFS media mount

```yaml
    persistence:
      media:
        type: nfs
        server: ${NFS_ADDRESS}
        path: ${NFS_MEDIA_PATH}
        advancedMounts:
          <service>:
            app:
              - path: /mnt/media           # Adjust subPath as needed
                subPath: library/Movies    # Example subdirectory within the NFS share
```

Available NFS variables: `NFS_ADDRESS` (the NFS server IP), `NFS_MEDIA_PATH` (root path).

## Persistent storage (non-NFS)

Default for most persistent data:
```yaml
    persistence:
      data:
        type: persistentVolumeClaim
        storageClass: ceph-block       # Default — block devices move with pods
        accessMode: ReadWriteOnce
        size: 10Gi
        advancedMounts:
          <service>:
            app:
              - path: /data
```

See `operators.md` for storage class selection guidance.

## ServiceAccount and RBAC

Use the root-level `serviceAccount` and `rbac` keys. `serviceAccount: create: true` enables a default ServiceAccount for the release; `rbac` defines Roles/ClusterRoles and their bindings. Bindings reference the serviceAccount via `identifier: default`.

```yaml
    # Root-level — same indentation as controllers:, persistence:, etc.
    serviceAccount:
      create: true
    rbac:
      roles:
        <service>:
          type: Role    # Role (namespace-scoped) or ClusterRole (cluster-scoped)
          rules:
            # Scope rules as tightly as possible — prefer resourceNames when applicable
            - apiGroups: [""]
              resources: [secrets]
              resourceNames: [<service>-credentials]   # Limit to specific resource(s)
              verbs: [get]
            - apiGroups: [cilium.io]
              resources: [ciliumnetworkpolicies]
              verbs: ["*"]
      bindings:
        <service>:
          type: RoleBinding    # RoleBinding or ClusterRoleBinding
          roleRef:
            identifier: <service>    # Matches the key under rbac.roles above
          subjects:
            - identifier: default    # References the serviceAccount created above
```

Reference implementations: `cluster/gitops/media/fileflows/job-tracker/hr.yaml` (Role), `cluster/gitops/security/teleport/resource-applier/hr.yaml` (ClusterRole + Role).

## Security context notes

- `readOnlyRootFilesystem: true` is the default. If the app writes to a path under `/tmp` or a config dir, mount an `emptyDir` volume there rather than disabling this flag
- `runAsUser`/`runAsGroup`: check the base image Dockerfile for a non-root user (e.g., `USER 1000:1000`). Root is occasionally acceptable when using the kata-container runtime class or `hostUsers: false` (note: `hostUsers: false` doesn't work with NFS mounts)
- If an app legitimately needs root (e.g., a CSI plugin or host-level network tool), document why in a comment
