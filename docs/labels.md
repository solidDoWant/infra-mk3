# Kubernetes resource labels

The following labels are used across multiple applications in the cluster:

| Key prefix               | Key name                             | Values  | Valid resources        | Required | Description                                                                                       |
| ------------------------ | ------------------------------------ | ------- | ---------------------- | -------- | ------------------------------------------------------------------------------------------------- |
| `app.kubernetes.io`      | `name`                               | String  | Workloads and Networks | Yes      | Name of the app a resource belongs to. Used for network policy rules.                             |
| `cilium.home.arpa`       | `bgpadvertisement.opnsense-peer`     | `true`  | CiliumBGPAdvertisement | No       | Opt-in to allow Cilium to the advertise routes to the OPNsense autonomous system.                 |
| `cilium.home.arpa`       | `node.bgp-enabled`                   | `true`  | Node                   | No       | Opt-in to allow Cilium to announce routes via BGP from the node.                                  |
| `cilium.home.arpa`       | `advertise`                          | `false` | Networks               | No       | Opt-out to stop Cilium from announcing the associated IP to BGP peers.                            |
| `external-dns.home.arpa` | `publish`                            | `true`  | Networks               | No       | Opt-in to allow publishing a DNS record to Cloudflare.                                            |
| `patches.flux.home.arpa` | `deployment.ignore-replicas`         | `true`  | Deployment             | No       | Opt-in to allow the HelmRelease owning a deployment from reverting changes to the replica count.  |
| `patches.flux.home.arpa` | `helmrelease.append-drift-detection` | `true`  | HelmRelease            | No       | Opt-in to append HelmRelease drift detection rules, to avoid overwriting existing values.         |
| `patches.flux.home.arpa` | `helmrelease.defaults`               | `false` | HelmRelease            | No       | Opt-out to allow prevent a HelmRelease from receiving "standard" defaults.                        |
| `patches.flux.home.arpa` | `helmrelease.default-src-namespace`  | `false` | HelmRelease            | No       | Opt-out to allow prevent a HelmRelease from referencing the flux-system namespace for the source. |
| `patches.flux.home.arpa` | `helmrepository.defaults`            | `false` | HelmRepository         | No       | Opt-out to allow for setting a different HelmRepository polling interval.                         |
| `patches.flux.home.arpa` | `kustomization.patches`              | `false` | Kustomization          | No       | Opt-out to not apply kustomization patches. Required for the root kustomization.                  |
| `patches.flux.home.arpa` | `namespace.can-prune`                | `true`  | Namespace              | No       | Opt-in to allow a namespace to be pruned if Flux thinks that it should be deleted.                |
| `patches.flux.home.arpa` | `statefulset.ignore-replicas`        | `true`  | StatefulSet            | No       | Opt-in to allow the HelmRelease owning a statefulset from reverting changes to the replica count. |
