# Authentik Authentication

Authentik handles **user authentication only** — not service-to-service auth.

**Strongly prefer OIDC** (native OAuth2/OIDC integration) over proxy forward-auth. Proxy forward-auth breaks many applications due to credential renewal behavior and requires manual UI configuration for certain settings. Only use proxy auth when the application has no OIDC support at all.

Every service with any Authentik integration requires:
- An Authentik blueprint Secret (labeled `k8s-sidecar.home.arpa/application: authentik`)
- One or more dedicated Discord roles in `cluster-secrets.sops.yaml` — services never share roles

---

## OIDC (preferred)

Use when the application supports native OIDC/OAuth2 login.

The blueprint registers an OAuth2 provider in Authentik. The app itself handles tokens — no outpost proxy needed.

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: authentik-<service>-application-blueprint
  labels:
    k8s-sidecar.home.arpa/application: authentik
type: Opaque
stringData:
  authentik-<service>-application-blueprint.yaml: |
    ---
    # yaml-language-server: $schema=https://goauthentik.io/blueprints/schema.json
    version: 1
    metadata:
      name: <Service> application
      labels:
        blueprints.goauthentik.io/description: OIDC provider for <Service>
    entries:
      - model: authentik_blueprints.metaapplyblueprint
        attrs:
          identifiers:
            name: Implicit provider authentication
          required: true
      - model: authentik_blueprints.metaapplyblueprint
        attrs:
          identifiers:
            name: Password authentication flow
          required: true
      - model: authentik_blueprints.metaapplyblueprint
        attrs:
          identifiers:
            name: Invalidation flow
          required: true
      - model: authentik_blueprints.metaapplyblueprint
        attrs:
          identifiers:
            name: Blueprint library
          required: true

      - model: authentik_providers_oauth2.oauth2provider
        id: <service>-provider
        identifiers:
          name: <Service>
        attrs:
          name: <Service>
          client_id: "${SECRET_<SERVICE>_AUTHENTIK_OIDC_CLIENT_ID}"
          client_secret: "${SECRET_<SERVICE>_AUTHENTIK_OIDC_CLIENT_SECRET}"
          client_type: confidential
          redirect_uris:
            - url: https://<service>.${SECRET_PUBLIC_DOMAIN_NAME}/auth/callback
              matching_mode: strict
          signing_key: !Find [authentik_crypto.certificatekeypair, [name, authentik Self-signed Certificate]]
          authentication_flow:
            !Find [authentik_flows.flow, [slug, password-authentication-flow]]
          authorization_flow:
            !Find [authentik_flows.flow, [slug, implicit-authorization-flow]]
          invalidation_flow:
            !Find [authentik_flows.flow, [slug, invalidation-flow]]
          access_token_validity: hours=4
          refresh_token_validity: days=2

      - model: authentik_core.application
        id: <service>-application
        identifiers:
          slug: <service>
        attrs:
          name: <Service>
          slug: <service>
          group: <Group>               # e.g. "Media access", "Dev tools"
          provider: !KeyOf <service>-provider
          policy_engine_mode: any
          meta_launch_url: https://<service>.${SECRET_PUBLIC_DOMAIN_NAME}

      - model: authentik_core.group
        id: <service>-group
        identifiers:
          name: <Service> access
        attrs:
          attributes:
            discord_role_id: "${SECRET_AUTHENTIK_<SERVICE>_DISCORD_ROLE_ID}"

      - model: authentik_policies.policybinding
        identifiers:
          order: 0
          group: !KeyOf <service>-group
          target: !KeyOf <service>-application
```

**Required secrets in `cluster-secrets.sops.yaml`:**
```yaml
SECRET_<SERVICE>_AUTHENTIK_OIDC_CLIENT_ID: "<id from authentik>"
SECRET_<SERVICE>_AUTHENTIK_OIDC_CLIENT_SECRET: "<secret from authentik>"
# One per role. Suffix `<SERVICE>` with `_<NAME (e.g. ADMIN, USER)>` if adding multiple roles.
SECRET_AUTHENTIK_<SERVICE>_DISCORD_ROLE_ID: "<discord role id>"
```

**No changes needed to HTTPRoute** — the app handles OIDC callback URLs itself.

---

## Proxy forward-auth (last resort only)

Use only when the app has no OIDC support. This mode intercepts every request through the Authentik embedded outpost (running in `authentik-server`). It breaks applications that don't handle cookie/header-based credential renewal well. All wiring below is declarative (GitOps) — no manual Authentik UI setup is required.

Additional requirements beyond OIDC blueprint:
1. Replace `oauth2provider` with `proxyprovider` in the blueprint
2. Add an outpost rule to the HTTPRoute (`/outpost.goauthentik.io` → `authentik-server.security:80`)
3. **Enroll the hostname in the gateway's Istio `AuthorizationPolicy`** (see below) — easy to miss, and nothing works without it
4. **Assign the new provider to the embedded outpost** (see below) — add it to the `!Find` list in `cluster/gitops/security/authentik/configuration/embedded-outpost/embedded-outpost-blueprint.yaml`
5. Configure the app to trust the `X-Authentik-*` headers (if it supports external auth mode)

> **The four pieces must all be present.** The blueprint registers the provider, the HTTPRoute rule exposes the `/outpost.goauthentik.io` callback path, the `AuthorizationPolicy` is what actually makes the gateway invoke the outpost (ext_authz) for the host, and the embedded-outpost blueprint assigns the provider so the outpost serves it. If the hostname is not in the `AuthorizationPolicy`, the gateway serves the app directly: **no redirect to Authentik, and no `X-authentik-*` headers reach the backend.** This is the single most common reason "auth silently does nothing."
>
> Forward-auth runs on the **embedded outpost** inside `authentik-server` (Postgres-backed sessions, shared across the server replicas — survives load-balancing and pod restarts). The standalone `authentik-outpost-proxy` was retired because its per-pod `/dev/shm` sessions returned HTTP 400 on the OAuth callback under multiple replicas. Because `!FindMany` is unavailable in this authentik version (PR #16942 unmerged), providers are assigned to the embedded outpost **explicitly** — add a `!Find` line for the new provider to `embedded-outpost-blueprint.yaml`:
>
> ```yaml
>     entries:
>       - model: authentik_outposts.outpost
>         identifiers:
>           managed: goauthentik.io/outposts/embedded
>         attrs:
>           providers:
>             - !Find [authentik_providers_proxy.proxyprovider, [name, <Service>]]   # <-- add the new provider here
> ```

```yaml
      # Replace the oauth2provider entry with this:
      - model: authentik_providers_proxy.proxyprovider
        id: <service>-provider
        identifiers:
          name: <Service>
        attrs:
          name: <Service>
          mode: forward_single
          external_host: https://<service>.${SECRET_PUBLIC_DOMAIN_NAME}
          intercept_header_auth: true
          authentication_flow:
            !Find [authentik_flows.flow, [slug, password-authentication-flow]]
          authorization_flow:
            !Find [authentik_flows.flow, [slug, implicit-authorization-flow]]
          invalidation_flow: !Find [authentik_flows.flow, [slug, invalidation-flow]]
          access_token_validity: hours=4
          refresh_token_validity: days=2
          property_mappings:
            - !Find [authentik_providers_oauth2.scopemapping, [name, "authentik default OAuth Mapping: Application Entitlements"]]
            - !Find [authentik_providers_oauth2.scopemapping, [name, "authentik default OAuth Mapping: OpenID 'email'"]]
            - !Find [authentik_providers_oauth2.scopemapping, [name, "authentik default OAuth Mapping: OpenID 'openid'"]]
            - !Find [authentik_providers_oauth2.scopemapping, [name, "authentik default OAuth Mapping: OpenID 'profile'"]]
            - !Find [authentik_providers_oauth2.scopemapping, [name, "authentik default OAuth Mapping: Proxy outpost reduced"]]
```

**Additional HTTPRoute rule** (add only for proxy auth):
```yaml
route:
  <service>:
    rules:
      - backendRefs:
          - identifier: <service>
            port: *web_port
      # Outpost rule — only needed for proxy forward-auth.
      # authentik-server runs the embedded outpost (Postgres-backed sessions,
      # shared across replicas); the standalone authentik-outpost-proxy was retired.
      - backendRefs:
          - name: authentik-server
            namespace: security
            port: 80
        matches:
          - path:
              type: PathPrefix
              value: /outpost.goauthentik.io
```

**Enroll the hostname in the Istio `AuthorizationPolicy`** (add only for proxy auth). Edit `cluster/gitops/networking/gateways/ingress/policies/authorization-policy.yaml` and add the service hostname to the `internal-gateway-authentik-auth` policy's `hosts` list:

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: internal-gateway-authentik-auth
spec:
  targetRef:
    kind: Gateway
    group: gateway.networking.k8s.io
    name: internal-gateway
  action: CUSTOM
  provider:
    name: authentik
  rules:
    - to:
        - operation:
            hosts:
              - radarr.${SECRET_PUBLIC_DOMAIN_NAME}
              - sonarr.${SECRET_PUBLIC_DOMAIN_NAME}
              - <service>.${SECRET_PUBLIC_DOMAIN_NAME}   # <-- add the new hostname here
```

**Required secrets:** Same `SECRET_AUTHENTIK_<SERVICE>_DISCORD_ROLE_ID`, but no OIDC client ID/secret needed.
