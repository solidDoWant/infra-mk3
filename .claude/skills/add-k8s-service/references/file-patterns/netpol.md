# CiliumNetworkPolicy

Every service requires a CiliumNetworkPolicy. Always add comments explaining what each rule allows and why.

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/cilium.io/ciliumnetworkpolicy_v2.json
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: <service>
specs:
  - description: <service>
    endpointSelector:
      matchLabels:
        app.kubernetes.io/name: <service>
        app.kubernetes.io/controller: <service>
        app.kubernetes.io/instance: <service>
    egress:
      # DNS resolution — required for all services to resolve cluster DNS
      - &dns_resolution
        toEndpoints:
          - matchLabels:
              io.kubernetes.pod.namespace: networking
              endpoints.netpols.home.arpa/cluster-dns: "true"
        toPorts:
          - ports:
              - port: "53"
                protocol: UDP
              - port: "53"
                protocol: TCP
            rules:
              dns:
                - matchPattern: "*"

      # PostgreSQL — access to the CNPG cluster (select only primary/rw pods)
      - toEndpoints:
          - matchLabels:
              cnpg.io/cluster: <service>-postgres-17
        toPorts:
          - ports:
              - port: "5432"
                protocol: TCP

      # Dragonfly/Redis — access to the cache cluster
      - toEndpoints:
          - matchLabels:
              app.kubernetes.io/name: <service>-dragonfly
              io.kubernetes.pod.namespace: <namespace>
        toPorts:
          - ports:
              - port: "6379"
                protocol: TCP

      # SMTP relay — for sending transactional emails
      - toEndpoints:
          - matchLabels:
              app.kubernetes.io/name: docker-postfix
              io.kubernetes.pod.namespace: email
        toPorts:
          - ports:
              - port: "587"
                protocol: TCP

      # External API — restrict to specific FQDNs, not broad internet access
      - toFQDNs:
          - matchPattern: api.example.com
        toPorts:
          - ports:
              - port: "443"
                protocol: TCP

    ingress:
      # Kubelet health checks — required for liveness/readiness probes
      - fromEntities:
          - host
        toPorts: &web_ports
          - ports:
              - port: "<web_port>"
                protocol: TCP

      # Gateway ingress — allows the internal gateway to reach this service
      - fromEndpoints:
          - matchLabels:
              io.kubernetes.pod.namespace: networking
              app.kubernetes.io/name: ingress-gateways
              gateway.networking.k8s.io/gateway-name: internal-gateway
        toPorts: *web_ports

      # Metrics scraping — allows the Victoria Metrics agent to scrape metrics
      - fromEndpoints:
          - matchLabels:
              io.kubernetes.pod.namespace: monitoring
              endpoints.netpols.home.arpa/metrics-scraper: "true"
        toPorts:
          - ports:
              - port: "<metrics_port>"
                protocol: TCP
  - description: <second-sub-service>
```

If there are multiple sub-services (e.g. an API, a frontend, etc.) then the netpol should be named for the service, and each specs entry description should be named after the sub-service.

## Label selectors

Pod labels used by app-template for controller selection follow this pattern:
```
app.kubernetes.io/name: <release-name>
app.kubernetes.io/controller: <controller-name>    # matches the key under `controllers:`
app.kubernetes.io/instance: <release-name>
```

Always verify these match the actual pod labels — they're set by app-template based on the release and controller names. For external charts, check what labels the chart applies.

## Custom labels for cross-service access

If other services need to select this service's pods in their network policies, add a custom label to the pod:

```yaml
# In hr.yaml under controllers.<name>.pod.labels:
endpoints.netpols.home.arpa/my-role: "true"
```

Then in other services' netpols:
```yaml
- toEndpoints:
    - matchLabels:
        endpoints.netpols.home.arpa/my-role: "true"
        io.kubernetes.pod.namespace: <namespace>
```

## Envoy sidecar netpol consideration

When using an Envoy sidecar for postgres mTLS, the app itself connects to `127.0.0.1:5432` (loopback — no policy needed). The Envoy sidecar container makes the actual egress connection to postgres, so the postgres egress rule applies to the whole pod (all containers share the same network namespace in Kubernetes).

## Multiple controllers (e.g., app + metrics exporter)

If the HelmRelease defines multiple controllers (e.g., main app and a separate exporter deployment), add a separate `specs` entry for each:

```yaml
specs:
  - description: <service> app
    endpointSelector:
      matchLabels:
        app.kubernetes.io/name: <service>
        app.kubernetes.io/controller: <service>
    egress: [...]
    ingress: [...]

  - description: <service> exporter
    endpointSelector: &exporter_selector
      matchLabels:
        app.kubernetes.io/name: <service>
        app.kubernetes.io/controller: exporter
    egress:
      - *dns_resolution
      # Exporter scrapes the main app
      - toEndpoints:
          - matchLabels:
              app.kubernetes.io/name: <service>
              app.kubernetes.io/controller: <service>
        toPorts:
          - ports:
              - port: "<web_port>"
                protocol: TCP
    ingress:
      # Kubelet health checks
      - fromEntities:
          - host
        toPorts: &metrics_ports
          - ports:
              - port: "<metrics_port>"
                protocol: TCP
      # Victoria Metrics agent
      - fromEndpoints:
          - matchLabels:
              io.kubernetes.pod.namespace: monitoring
              endpoints.netpols.home.arpa/metrics-scraper: "true"
        toPorts: *metrics_ports
```
