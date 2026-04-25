---
name: add-k8s-service
description: Add a new service to the Kubernetes cluster. Use this skill whenever the user wants to deploy a new application, workload, or service to the cluster — e.g. "add X to the cluster", "deploy Y", "set up Z service", "I want to run X in kubernetes". Also use when the user asks about how to structure a new service or what files to create for a new deployment.
---

# Add New Kubernetes Service

This skill guides through adding a new service to the cluster, following the established patterns in this repo. The cluster uses Flux CD for GitOps, Cilium for networking, cert-manager for certificates, CloudNative-PG/Dragonfly/RabbitMQ operators for backends, and Authentik for user authentication.

**Critical rule: Always check with the user and get confirmation before writing any files.**

## Step 1: Research First

Before asking the user anything, delegate research to a sub-agent to keep the main context clean. Launch an `Explore` sub-agent with a prompt along these lines:

```
Research the "<service>" application for deployment to a Kubernetes cluster. Find and report:

1. Helm chart: Search https://kubesearch.dev for "<service>" — note chart name, repository URL, and latest version if found.
2. Container image: Check whether ghcr.io/home-operations/<name> exists and what the latest tag is. Otherwise note the canonical image and latest tag.
3. Default port(s) and how the app is configured (env vars, config file, CLI flags).
4. PostgreSQL support: does it support Postgres? If so, does it support native TLS client certificates? Check in this order:
   a. Does the app accept a full DSN/connection URL (e.g. DATABASE_URL=postgres://...)? If yes, the answer is almost certainly yes — Go (pgx/lib/pq), libpq, Npgsql, JDBC, and most drivers support sslcert/sslkey/sslrootcert as DSN query parameters even if they are not documented as standalone env vars. Verify by checking what driver/library the app uses.
   b. Does it have explicit sslcert/sslkey/sslrootcert config options (env vars, config file fields)?
   c. If docs are ambiguous, check the source — search the repo for how the DB connection is constructed.
   Only conclude "does not support native TLS" if none of the above apply.
5. Prometheus metrics: does it expose a /metrics endpoint? Does the upstream Helm chart (if any) have built-in serviceMonitor support?
6. Grafana dashboards: are there official dashboards on grafana.com or in the project repo? Note IDs or URLs.
7. Common external dependencies (databases, caches, queues, object storage). For each dependency, check native TLS support using the same reasoning as item 4: if the app accepts a connection URL (e.g. redis://, rediss://, amqp://, etc.), check whether the underlying client library supports TLS parameters in the URL or config — most do even when not explicitly documented.
8. Language/runtime (affects TLS cert key algorithm — .NET/Npgsql requires ECDSA, not Ed25519).

Return a structured summary. Do not write any files — research only.

For each finding, include the source URL and a brief note on what confirmed it (e.g. "docs page", "source file", "README"). If a finding came from source code, include the file path or line. Mark findings as "not found" or "unclear" rather than omitting them — this helps the implementing agent know what still needs verification.
```

Use the sub-agent's structured summary to inform the plan. Then gather the remaining unknowns from the user in a single grouped set of questions. Don't ask about things the sub-agent already found.

## Step 2: Propose the Plan

Before writing anything, present a complete plan. Be concrete — give actual paths, names, and reasoning for every decision.

### 2a: Namespace / Domain

Read `cluster/gitops/` to get the current list of domains — don't rely on any hardcoded list. Map the service to an existing domain. If none fit, propose a new domain with justification.

Each domain corresponds to a Kubernetes namespace of the same name. Check that the namespace exists (`cluster/gitops/<domain>/namespace.yaml`) and that there's a namespace issuer at `cluster/gitops/<domain>/issuers/` if the service needs postgres mTLS.

### 2b: Directory Structure

Standard layout:
```
cluster/gitops/<domain>/<service>/
├── ks.yaml                    # One or more Flux Kustomization resources
└── app/
    ├── hr.yaml                # HelmRelease
    ├── netpol.yaml            # CiliumNetworkPolicy (always required)
    └── <optional resources>
```

Optional app resources (create only when needed):
- `pdb.yaml` — standalone PodDisruptionBudget (only if not using app-template, which has this built in; requires replicas ≥ 2)
- `dashboard.yaml` — GrafanaDashboard resource (if dashboards available)
- `authentik-<name>-application-blueprint.yaml` — Authentik OIDC blueprint (if auth needed)
- `<name>.sops.yaml` — SOPS-encrypted secrets (user creates/encrypts these)
- `envoy-config/` — Envoy config ConfigMaps (only if app needs Envoy sidecar for backend mTLS)

If backends are needed, add:
```
└── backend/
    └── postgres/
    │   ├── auth/hr.yaml       # mTLS client certs (always deploy before cluster)
    │   └── 17/hr.yaml         # CNPG cluster via cluster/charts/postgres/cluster
    └── redis/hr.yaml          # Dragonfly cluster via cluster/charts/dragonfly/cluster
    └── rabbitmq/              # RabbitMQ User + Permission CRDs
    └── s3/bucketclaim.yaml    # ObjectBucketClaim for Rook Ceph S3
```

Multiple Flux Kustomizations are needed when the service has:
- Backend resources (deploy backends before app)
- Multiple distinct HelmReleases (e.g., separate chart per component)
- Post-install configuration logic (separate KS with `dependsOn` on the main one)

### 2c: Helm Chart

**Default: `app-template` v4.6.2** from `bjw-s-charts`. Use this for almost everything. Only deviate when the upstream chart provides substantial value that would require significant duplication to replicate in app-template (complex operator-managed resources, multi-component deployments with complex inter-service wiring, etc.). If proposing an external chart, name it and explain specifically why.

If using an external chart that isn't already in `cluster/gitops/flux-system/flux/sources/helm/`, a new HelmRepository file is needed (see `references/file-patterns/flux-sources.md`).

### 2d: Backend Services

**Prefer PostgreSQL over embedded/local databases** (SQLite, BoltDB, etc.) whenever the application supports it — PostgreSQL provides automated backups, HA, mTLS, and consistent operations across the cluster.

For each backend type, name the operator/chart:
- **PostgreSQL**: `cluster/charts/postgres/cluster` + `cluster/charts/postgres/auth` — deploy `auth` first. Default 2 instances (HA).
- **Redis/Cache**: `cluster/charts/dragonfly/cluster` — custom chart wrapping the Dragonfly operator CRD. Default 2 instances (HA).
- **Message queue**: RabbitMQ operator CRDs — `RabbitMQCluster` (3 replicas for quorum), `User`, `Permission`, plus dedicated certificate infrastructure. See `references/file-patterns/backends-rabbitmq.md` for the full setup. **Flag RabbitMQ usage to the user** — the raw CRD approach is complex enough that it should probably be wrapped in a dedicated chart (like `cluster/charts/postgres/` or `cluster/charts/dragonfly/`) before deploying. Raise this with the user and confirm whether they want to proceed with raw CRDs or create a chart first.
- **S3 object storage**: `ObjectBucketClaim` with `storageClassName: ssd-replicated-object`. Always create a Kyverno `Policy` to transform the OBC-generated ConfigMap/Secret into app-specific key names and construct the full S3 endpoint URL.
- **SMTP relay**: Use the shared `docker-postfix` service at `docker-postfix.email.svc.cluster.local:587`

If a new backend type is required that has no existing operator or pattern, flag this before proceeding.

Prefer operator-managed resources over manual configuration, but note: postgres database config and schema are managed via the backend charts, not direct CNPG CRDs.

### 2e: mTLS to Backend Services

The cluster does not use Istio for pod-to-pod mTLS — only cert-manager and explicit TLS config per connection.

For each backend that supports TLS:
- Check whether the application natively supports TLS client certificates. If the app accepts a full DSN/connection URL, check whether the underlying driver supports TLS params in the DSN — Go (pgx/lib/pq), libpq, Npgsql, JDBC and most drivers do, even when not explicitly documented. This is the most common case and should be verified before concluding Envoy is needed.
- If yes (native TLS): use cert-manager client certs, mount as volumes, configure via the app's native mechanism
- If no: use an Envoy proxy sidecar (image: `envoyproxy/envoy:contrib-v1.35.3` or latest). The app connects to `127.0.0.1:<port>` unencrypted; Envoy proxies to the real backend over mTLS. See `references/operators.md` for the full pattern and `references/envoy-sidecar-pg.yaml` for a reusable Envoy config template. Reference implementation: `cluster/gitops/development/harbor/app/`

Note: Redis/Dragonfly mTLS via Envoy is currently broken upstream (envoyproxy/envoy#41659). Flag this if Dragonfly is needed with an app that doesn't support native TLS.

### 2f: User Authentication

Authentik handles **user authentication only** — not service-to-service auth.

For web UIs, always prefer native **OIDC** integration if the app supports it. Configure the app to use Authentik as an OIDC provider directly. This is more reliable than proxy auth and avoids credential renewal issues.

Only use **Authentik proxy forward-auth** as an absolute last resort for apps with no OIDC support whatsoever — proxy forward-auth breaks many applications due to credential renewal behavior, and some configuration requires manual Authentik UI setup (missing blueprint support).

Every service with Authentik integration (OIDC or proxy) requires:
1. An Authentik blueprint Secret labeled `k8s-sidecar.home.arpa/application: authentik`
2. A dedicated Discord role (never shared) — `SECRET_AUTHENTIK_<SERVICE>_DISCORD_ROLE_ID` in `cluster-secrets.sops.yaml`
3. For proxy auth only: an HTTPRoute rule forwarding `/outpost.goauthentik.io` to `authentik-outpost-proxy.security:80`

**Never add the service to the `external-gateway`** unless explicitly requested.

The cluster has two gateways, both using `SECRET_PUBLIC_DOMAIN_NAME`:
- `internal-gateway` — reachable only from within the local network (DNS and firewall restrict access). **This is the default for all services.** A web UI on the internal gateway is still browsable from home — it is not "unexposed", just not internet-facing.
- `external-gateway` — internet-accessible. Only use when the service explicitly needs to be reachable from outside the local network (e.g. a public-facing API or webhook receiver).

When a service has a web UI, always include an HTTPRoute to `internal-gateway`. Do not ask the user whether to expose it — the answer is always yes, on the internal gateway, unless they say otherwise.

### 2g: Monitoring

For Prometheus metrics:
1. **Chart-native serviceMonitor**: If the Helm chart has a built-in `serviceMonitor.enabled` or equivalent option, use it — the Victoria Metrics operator auto-converts ServiceMonitor resources to VMServiceScrape. This is preferred.
2. **Standalone VMServiceScrape**: Use when the chart has no built-in scraping support, or when you need VM-specific features (e.g., `discoveryRole: service` to prevent duplicate scraping from HA exporters).
3. **App-template `serviceMonitor`**: App-template v4 supports `serviceMonitor` inline in values.

For Grafana dashboards: if decent dashboards exist (on grafana.com, in the project repo, or elsewhere), include them as a `GrafanaDashboard` resource. Use `grafanaCom.id`, `url`, or `configMapRef` as appropriate.

### 2h: Secrets

List every secret the user must create. Be specific about:
- Secret name, namespace, and keys required
- Whether values come from Flux substitution variables or literal values
- Remind them to run `sops -e -i <file>.sops.yaml` after creating each file

The skill cannot encrypt secrets — the user must do this.

## Step 3: Ask for Confirmation

Present the full plan as a concise summary covering all 8 areas above. Include open questions and flag anything unusual (new backend type, external-gateway, proxy auth, multi-writer storage, etc.). Wait for confirmation before proceeding.

## Step 4: Write the Files

Write files group by group: flux source (if new), backend KS + resources, then app resources. After each group, briefly note what's next.

### Standards for every service

**Helm chart version**: Use `app-template` 4.6.2. Pin all images and chart versions to specific version tags (not `latest`). Checksums are ideal but tags are acceptable for readability.

**Container images**: Check for a `ghcr.io/home-operations/<name>` image first. These generally have better security and run rootless.

**Security context** (adapt if the application requires different settings):
```yaml
securityContext:
  readOnlyRootFilesystem: true      # If app needs tmp writes, mount an emptyDir instead of disabling this
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

**Pod security context**: Set `runAsUser`/`runAsGroup` based on the base image's defined non-root user, if it has one. Root is occasionally acceptable with kata-container runtime or `hostUsers: false` (note: `hostUsers: false` doesn't work with NFS mounts). Check app requirements.
```yaml
defaultPodOptions:
  securityContext:
    runAsNonRoot: true
    runAsUser: <uid from image>
    runAsGroup: <gid from image>
    fsGroup: <gid from image>
    fsGroupChangePolicy: OnRootMismatch
  dnsConfig:
    options:
      - name: ndots
        value: "1"
```

**No TZ env var** — k8tz handles timezone injection automatically via mutating webhook.

**HA by default**: Services should run with replicas ≥ 2 where the application supports it. Backends (PostgreSQL, Dragonfly) default to 2 instances. RabbitMQ requires 3 replicas for quorum. Availability is a priority in this cluster.

**Resource limits**: Always set `resources.limits.memory` equal to `resources.requests.memory`, if a memory request is set. CPU limits should be omitted (unbounded) to allow bursting.

**PodDisruptionBudget**: Required when replicas ≥ 2. For app-template, configure per-controller inline:
```yaml
controllers:
  <name>:
    replicas: 2
    podDisruptionBudget:
      enabled: true
      minAvailable: 1
```
For non-app-template charts, use a standalone `pdb.yaml`.

**CiliumNetworkPolicy**: Always required. Every service needs one. See `references/file-patterns/netpol.md` for the template and required rules. Always add comments explaining what each egress/ingress rule allows and why.

**HTTPRoute**: Always use `internal-gateway` in namespace `networking`. Include the Authentik outpost rule (`/outpost.goauthentik.io` → `authentik-outpost-proxy.security:80`) only when using proxy forward-auth, not OIDC.

**Certificate mount paths**: Mount mTLS certs under `/etc/<app>/certs/` (e.g., `/etc/radarr/certs/postgres/`), not a generic `/certs/` path.

**Flux Kustomization dependencies** — determine based on what the service actually uses:
- Always: `prometheus-crds`
- If HTTPRoute: `gateway-crds`
- If GrafanaDashboard: `grafana-crds`
- If postgres: `cluster-issuers`, `<namespace>-namespace-issuer`, `cloudnative-pg`, `rook-ceph-cluster`
- If Dragonfly: `dragonfly-operator`, `<namespace>-namespace-issuer`
- If RabbitMQ: `rabbitmq-crds`
- App must depend on its backend Kustomization(s)

### After writing files

The skill should handle all of the following automatically (don't tell the user to do them):
- Add the new service's `ks.yaml` to the domain's `kustomization.yaml`
- If this is a new domain: create `namespace.yaml`, `kustomization.yaml`, and `issuers/` if postgres is used

The user must handle:
- Creating and SOPS-encrypting all secret files
- For OIDC: creating the client application in Authentik and adding credentials to `cluster-secrets.sops.yaml`
- Creating the Discord role and adding `SECRET_AUTHENTIK_<SERVICE>_DISCORD_ROLE_ID` to `cluster-secrets.sops.yaml`

## Reference Files

**Do not blindly copy these**. Use them as a starting point as appropriate, but consider every line and setting.

- `references/file-patterns/ks.md` — Flux Kustomization templates and dependency logic
- `references/file-patterns/hr-app-template.md` — HelmRelease (app-template), security contexts, PDB, monitoring, volumes
- `references/file-patterns/netpol.md` — CiliumNetworkPolicy templates with annotated rules
- `references/file-patterns/auth.md` — Authentik OIDC and proxy blueprint templates
- `references/file-patterns/backends-postgres.md` — PostgreSQL (CNPG) chart values, namespace issuer setup
- `references/file-patterns/backends-dragonfly.md` — Dragonfly (Redis-compatible cache) chart values
- `references/file-patterns/backends-rabbitmq.md` — RabbitMQ cluster, cert infrastructure, per-consumer resources
- `references/file-patterns/backends-s3.md` — ObjectBucketClaim and Kyverno transformation policy
- `references/file-patterns/monitoring.md` — ServiceMonitor, VMServiceScrape, GrafanaDashboard
- `references/file-patterns/flux-sources.md` — Adding new HelmRepository sources
- `references/operators.md` — Envoy sidecar pattern, storage class guide, backend operator details
- `references/envoy-sidecar-pg.yaml` — Reusable Envoy config for PostgreSQL mTLS proxying
- `references/envoy-sidecar-redis.yaml` — Reusable Envoy config for Dragonfly/Redis mTLS proxying
