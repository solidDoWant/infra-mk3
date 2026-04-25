# Backend — Dragonfly (Redis-compatible cache)

Uses a custom chart that wraps the Dragonfly operator CRD. Default `instances: 2` provides HA with topology spread across nodes.

Dragonfly mTLS requires a namespace issuer — see the **Namespace Issuer** section in `backends-postgres.md` if one doesn't exist for the target namespace yet.

## backend/redis/hr.yaml

```yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <service>-dragonfly
spec:
  interval: 5m
  chart:
    spec:
      chart: ./cluster/charts/dragonfly/cluster
      reconcileStrategy: Revision
      sourceRef:
        kind: GitRepository
        namespace: flux-system
        name: infra-mk3
  values:
    serviceName: <service>
    instances: 2         # HA — topology spread across nodes is handled by the chart
    teleportDomainName: teleport.${SECRET_PUBLIC_DOMAIN_NAME}
    certificates:
      serving:
        issuerRef:
          name: <namespace>-intermediary-ca
    users:
      <service>:
        username: <service>
    netpol:
      applicationAccess:
        selectors:
          # Add one entry per set of pods that need cache access. Scope tightly.
          - matchLabels:
              app.kubernetes.io/name: <service>
              app.kubernetes.io/instance: <service>
    resources:
      requests:
        cpu: 100m
        memory: 640Mi    # Dragonfly requires 256Mi per thread; default 2 threads = 512Mi + overhead
      limits:
        memory: 640Mi    # Always set limits = requests for memory when requests are set
```

Connection: use the TLS connection string with client certs mounted under `/etc/<service>/certs/redis/`.

**Note:** If the app doesn't support native TLS to Dragonfly, an Envoy sidecar can proxy the connection — see `references/envoy-sidecar-redis.yaml`. This works for most applications. The one exception is apps that use multiple Redis database indexes (`SELECT N`): the Envoy redis_proxy filter does not support this (envoyproxy/envoy#41659). Check whether the app uses multiple indexes before choosing this path.
