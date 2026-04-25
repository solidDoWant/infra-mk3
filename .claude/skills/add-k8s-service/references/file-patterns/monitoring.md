# Monitoring: Metrics and Dashboards

The cluster uses Victoria Metrics. The VM operator automatically converts `ServiceMonitor` resources to `VMServiceScrape`, so both work — but use the chart-native option when available.

---

## Chart-native serviceMonitor (preferred when available)

If the Helm chart (app-template or external) has a built-in `serviceMonitor` option, use it:

**app-template:**
```yaml
    serviceMonitor:
      <service>:
        endpoints:
          - port: metrics
            interval: 1m
```

**External charts** (check the chart's values.yaml for the exact field name):
```yaml
    metrics:
      enabled: true
      serviceMonitor:
        enabled: true
```

This is the preferred approach — fewer files, chart manages the resource lifecycle.

---

## Standalone VMServiceScrape

Use when:
- The chart has no built-in serviceMonitor option
- You need VM-specific features (e.g., `discoveryRole: service` to avoid scraping both pod and service for HA deployments, `metricRelabelConfigs`, etc.)

```yaml
---
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMServiceScrape
metadata:
  name: <service>-metrics
  labels:
    app.kubernetes.io/part-of: <service>
    app.kubernetes.io/component: monitoring
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: <service>
      app.kubernetes.io/service: <service>-metrics
      app.kubernetes.io/instance: <service>
  endpoints:
    - port: metrics
      interval: 1m
  jobLabel: <service>-metrics
  # Use discoveryRole: service instead of the default (endpoint) when the service
  # has multiple replicas that would otherwise be scraped individually — all replicas
  # contain identical data, so only one scrape is needed.
  discoveryRole: service
```

---

## Standalone ServiceMonitor

Use only when an external chart creates a `Service` with Prometheus labels and the chart doesn't expose serviceMonitor in its values. The VM operator will auto-convert it.

```yaml
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: <service>
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: <service>
  endpoints:
    - port: metrics
      interval: 1m
      path: /metrics
```

---

## GrafanaDashboard

If dashboards are available, always include them. Check:
1. [grafana.com/grafana/dashboards](https://grafana.com/grafana/dashboards) — search by project name
2. The project's GitHub repo (often has a `grafana-dashboard.json` or links to grafana.com)
3. The Helm chart values (`grafanaDashboard.enabled`, `dashboards:`, etc.) — some charts deploy dashboards automatically

**From grafana.com by ID:**
```yaml
---
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: <service>
spec:
  instanceSelector:
    matchLabels:
      grafana.home.arpa/instance: grafana
  grafanaCom:
    id: <dashboard-id>     # The numeric ID from the grafana.com URL
  datasources:
    - datasourceName: VictoriaMetrics
      inputName: DS_PROMETHEUS     # Common placeholder name in community dashboards
```

**From a URL (e.g., project GitHub):**
```yaml
---
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: <service>
spec:
  instanceSelector:
    matchLabels:
      grafana.home.arpa/instance: grafana
  url: https://raw.githubusercontent.com/<org>/<repo>/refs/tags/<version>/assets/grafana-dashboard.json
  datasources:
    - datasourceName: VictoriaMetrics
      inputName: DS_PROMETHEUS
```

**From a ConfigMap (for local/customized dashboards):**
```yaml
---
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: <service>
spec:
  allowCrossNamespaceImport: true
  instanceSelector:
    matchLabels:
      grafana.home.arpa/instance: grafana
  configMapRef:
    key: dashboard.json
    name: <service>-dashboard
```

**Note:** `allowCrossNamespaceImport: true` is needed when the GrafanaDashboard resource is in a namespace other than where Grafana is running (`monitoring`).
