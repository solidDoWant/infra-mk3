# Kubernetes resource labels

The following labels are used across multiple applications in the cluster:

| Key prefix                    | Key name                             | Values   | Valid resources        | Required | Description                                                                                       |
| ----------------------------- | ------------------------------------ | -------- | ---------------------- | -------- | ------------------------------------------------------------------------------------------------- |
| `app.kubernetes.io`           | `name`                               | String   | Workloads and Networks | Yes      | Name of the app a resource belongs to. Used for network policy rules.                             |
| `cilium.home.arpa`            | `bgpadvertisement.opnsense-peer`     | `true`   | CiliumBGPAdvertisement | No       | Opt-in to allow Cilium to the advertise routes to the OPNsense autonomous system.                 |
| `cilium.home.arpa`            | `node.bgp-enabled`                   | `true`   | Node                   | No       | Opt-in to allow Cilium to announce routes via BGP from the node.                                  |
| `cilium.home.arpa`            | `advertise`                          | `false`  | Networks               | No       | Opt-out to stop Cilium from announcing the associated IP to BGP peers.                            |
| `descheduler.home.arpa`       | `enable-lifetime-eviction`           | `false`  | Pods                   | No       | Opt-out to stop Descheduler from evicting pods over a set age.                                    |
| `external-dns.home.arpa`      | `publish`                            | `true`   | Networks               | No       | Opt-in to allow publishing a DNS record to Cloudflare.                                            |
| `grafana.home.arpa`           | `instance`                           | String   | Grafana                | Yes      | Name of the Grafana instance, for CR selection.                                                   |
| `k8s-sidecar.home.arpa`       | `application`                        | String   | ConfigMaps and Secrets | No       | Opt-in to load the resource into the configured application.                                      |
| `kyverno.home.arpa`           | `ksm-custom-resource-config`         | `true`   | ConfigMaps             | No       | True to load the file as a kube-state-metrics custom resource state metric config                 |
| `kyverno.home.arpa`           | `reload`                             | `true`   | ConfigMaps and Secrets | No       | True to reload attached workloads when changed                                                    |
| `patches.flux.home.arpa`      | `deployment.ignore-replicas`         | `true`   | Deployment             | No       | Opt-in to allow the HelmRelease owning a deployment from reverting changes to the replica count.  |
| `patches.flux.home.arpa`      | `helmrelease.append-drift-detection` | `true`   | HelmRelease            | No       | Opt-in to append HelmRelease drift detection rules, to avoid overwriting existing values.         |
| `patches.flux.home.arpa`      | `helmrelease.defaults`               | `false`  | HelmRelease            | No       | Opt-out to prevent a HelmRelease from receiving "standard" defaults.                              |
| `patches.flux.home.arpa`      | `helmrelease.default-src-namespace`  | `false`  | HelmRelease            | No       | Opt-out to prevent a HelmRelease from referencing the flux-system namespace for the source.       |
| `patches.flux.home.arpa`      | `helmrelease.skip-crds`              | `true`   | HelmRelease            | No       | Opt-in to prevent a HelmRelease from installing CRDs.                                             |
| `patches.flux.home.arpa`      | `helmrepository.defaults`            | `false`  | HelmRepository         | No       | Opt-out to allow for setting a different HelmRepository polling interval.                         |
| `patches.flux.home.arpa`      | `kustomization.patches`              | `false`  | Kustomization          | No       | Opt-out to not apply kustomization patches. Required for the root kustomization.                  |
| `patches.flux.home.arpa`      | `namespace.can-prune`                | `true`   | Namespace              | No       | Opt-in to allow a namespace to be pruned if Flux thinks that it should be deleted.                |
| `patches.flux.home.arpa`      | `statefulset.ignore-replicas`        | `true`   | StatefulSet            | No       | Opt-in to allow the HelmRelease owning a statefulset from reverting changes to the replica count. |
| `root-ceph.flux.home.arpa`    | `node.cluster-enabled`               | `true`   | StatefulSet            | No       | Opt-in to allow the using the node for a Rook-Ceph cluster, including OSDs.                       |
| `endpoints.netpols.home.arpa` | `cluster-dns`                        | `true`   | Pod                    | No       | Indicates that the labeled pod a DNS resolver for in-cluster resources.                           |
| `endpoints.netpols.home.arpa` | `metrics-scraper`                    | `true`   | Pod                    | No       | Indicates that the labeled pod is the source of metric scraping requests.                         |
| `external.netpols.home.arpa`  | `ingress.internet`                   | `true`   | Pod                    | No       | Opt-in to allow pod access from the Internet.                                                     |
| `external.netpols.home.arpa`  | `egress.internet`                    | `true`   | Pod                    | No       | Opt-in to allow pod access to the Internet.                                                       |
| `external.netpols.home.arpa`  | `ingress.intranet`                   | `true`   | Pod                    | No       | Opt-in to allow pod access from the intranet outside of the cluster.                              |
| `external.netpols.home.arpa`  | `unifi-aps`                          | `true`   | Pod                    | No       | Opt-in to allow pod access to and from UniFi APs.                                                 |
| `teleport.home.arpa`          | `database.enabled`                   | `true`   | TeleportDatabaseV3     | No       | Opt-in to allow Teleport to pick up the database resource.                                        |
| `zfs.home.arpa`               | `node.local-storage-enabled`         | `true`   | Node                   | No       | Opt-in to allow using the node for local ZFS-based storage.                                       |
| `zfs.home.arpa`               | `node.local-storage-deployed`        | `true`   | Node                   | No       | Indicates if the node local storage zpool has been deployed.                                      |
| `zfs.home.arpa`               | `node.local-storage-config-map`      | `String` | Node                   | No       | Indicates the last ZFS deployment script version that was successfully ran.                       |
| `zfs.home.arpa`               | `node.local-storage-scrub`           | `true`   | Node                   | No       | Indicates if the node local storage zpool should be immediately scrubbed.                         |

# Kubernetes resource annotations

The following annotations are used across multiple applications in the cluster:

| Key prefix          | Key name                  | Values | Valid resources | Required | Description                                                        |
| ------------------- | ------------------------- | ------ | --------------- | -------- | ------------------------------------------------------------------ |
| `kyverno.home.arpa` | `reload-tag`              | String | Workloads       | No       | Random value added by Kyverno to trigger a reload of a workflow    |
| `talos.home.arpa`   | `installer-image`         | String | Node            | Yes      | Full image name (without tag) for auto updates                     |
| `zfs.home.arpa`     | `node.pool-drive-matcher` | String | Node            | No       | File path matcher for drives that should be included in a ZFS pool |
