# This block should define all high-level configuration for the deployment.
locals {
  namespace     = "development"
  storage_class = "ssd-replicated-3x"

  labels = {
    "app.kubernetes.io/name"     = "coder-workspace"
    "app.kubernetes.io/instance" = "coder-workspace-${data.coder_workspace.me.id}"
    "app.kubernetes.io/part-of"  = "coder"
    "com.coder.resource"         = "true"
    "com.coder.workspace.id"     = data.coder_workspace.me.id
    "com.coder.workspace.name"   = data.coder_workspace.me.name
    "com.coder.user.id"          = data.coder_workspace_owner.me.id
    "com.coder.user.username"    = data.coder_workspace_owner.me.name
  }

  annotations = {
    "com.coder.user.email" = data.coder_workspace_owner.me.email
    # Unfortunately kata containers fails to start with this because the base image already
    # has some of the files that are added via volume mounts.
    "k8tz.io/inject" = "false"
  }

  uid = 1000
  gid = local.uid

  # NFS bulk storage. A single mount of the pool root exposes every share
  # underneath it (e.g. /mnt/bulk-pool-01/media), provided the NFS server
  # exports the parent path - the client never enumerates individual shares.
  # These mirror NFS_ADDRESS / the parent of NFS_MEDIA_PATH from the Flux
  # cluster-config; Flux variable substitution does not reach this template
  # (it is pushed with `coder templates push`), so the values are inlined.
  nfs_address    = "10.2.3.1"
  nfs_path       = "/mnt/bulk-pool-01"
  nfs_mount_path = "/mnt/bulk-pool-01"

  # Cluster PKI root CA. The root-ca-pub-cert secret is replicated into every
  # namespace by the extract-root-ca-certificate Kyverno ClusterPolicy. Mounting
  # ca.crt into Ubuntu's CA drop-in dir (+ update-ca-certificates on start) makes
  # every process in the pod trust the cluster's internal CA automatically.
  cluster_ca_secret     = "root-ca-pub-cert"
  cluster_ca_mount_path = "/usr/local/share/ca-certificates/cluster-pki-root.crt"

  # Public domain (SECRET_PUBLIC_DOMAIN_NAME), read from the Flux-substituted
  # coder-workspace-cluster-info ConfigMap. The template files are pushed
  # out-of-band so they never see Flux substitution, and the coder access_url is
  # the internal service URL (coder.development.svc.cluster.local), not the
  # public domain. teleport.<public-domain> resolves to the internal ingress
  # gateway (allowed by the netpol egress rule below).
  public_domain  = data.kubernetes_config_map.cluster_info.data["public_domain_name"]
  teleport_proxy = "teleport.${local.public_domain}:443"

  env_vars = {
    CODER_TELEMETRY_ENABLE           = "false"
    CODER_AGENT_TOKEN                = coder_agent.main.token
    CODER_DERP_SERVER_STUN_ADDRESSES = "disable"
    # Node does not consult the system trust store; point it at the mounted CA so
    # node-based tooling (e.g. Claude Code) also trusts the cluster PKI root.
    NODE_EXTRA_CA_CERTS = local.cluster_ca_mount_path
    # Default the Teleport proxy so `tsh login` works with no flags.
    TELEPORT_PROXY = local.teleport_proxy
  }

  pvcs = merge(
    {
      home = {
        size_gb    = data.coder_parameter.home_disk_size.value
        mount_path = "/home/coder"
      }

      workspace = {
        size_gb    = data.coder_parameter.workspace_disk_size.value
        mount_path = "/workspace"
      }
    },
    # Persistent Nix store (single-user install puts the store at /nix). Only
    # created when Nix is enabled, so packages are cached across restarts instead
    # of being re-downloaded on every boot.
    local.enable_nix ? {
      "nix-store" = {
        size_gb    = data.coder_parameter.nix_store_disk_size.value
        mount_path = "/nix"
      }
    } : {}
  )

  runtime_class = "kata"

  blackhole_domains = [
    # Additional "phone home" block in case the telemetry env var is ignored.
    "v1.telemetry.coder.com"
  ]
  # This is just an address in the TEST-NET-3 range per RFC 5737, which should be
  # a bogon address.
  blackhole_address = "203.0.113.1"

  name = "coder-workspace-${data.coder_workspace.me.id}"

  coder_labels = {
    "app.kubernetes.io/name"     = "coder"
    "app.kubernetes.io/part-of"  = "coder"
    "app.kubernetes.io/instance" = "coder"
  }
}

# Parameters
locals {
  workspace_resources_order_start = local.claude_order_start + local.claude_size
  workspace_resources_size        = 8
}

data "coder_parameter" "enable_nfs" {
  name         = "enable_nfs"
  display_name = "Mount NFS storage"
  description  = "Mount the bulk-pool-01 NFS storage (all shares) at ${local.nfs_mount_path}"
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/emojis/1f4c1.png"
  order        = local.workspace_resources_order_start + 7
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores available"
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = local.workspace_resources_order_start + 0
  form_type    = "slider"
  type         = "number"

  validation {
    min = 1
    max = 8
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of available memory in GB"
  default      = "4"
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = local.workspace_resources_order_start + 1
  form_type    = "slider"
  type         = "number"

  validation {
    min = 2
    max = 16
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home directory disk in GB"
  default      = "10"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = true
  order        = local.workspace_resources_order_start + 2

  validation {
    min       = 1
    max       = 100
    monotonic = "increasing"
  }
}

data "coder_parameter" "workspace_disk_size" {
  name         = "workspace_disk_size"
  display_name = "Workspace disk size"
  description  = "The size of the workspace directory disk in GB"
  default      = "10"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = true
  order        = local.workspace_resources_order_start + 3

  validation {
    min       = 1
    max       = 100
    monotonic = "increasing"
  }
}

data "coder_parameter" "enable_gpu" {
  name         = "enable_gpu"
  display_name = "GPU"
  description  = "Attach an Intel GPU to the workspace"
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = local.workspace_resources_order_start + 4
}

data "coder_parameter" "gpu_type" {
  name         = "gpu_type"
  display_name = "GPU type"
  description  = "Which GPU to attach. Arc Pro = discrete B40 card; Iris Xe = CPU integrated GPU"
  type         = "string"
  default      = "arc-pro"
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = local.workspace_resources_order_start + 5

  option {
    name  = "Arc Pro (discrete)"
    value = "arc-pro"
  }
  option {
    name  = "Iris Xe (integrated)"
    value = "iris-xe"
  }
}

data "coder_parameter" "gpu_admin_access" {
  name         = "gpu_admin_access"
  display_name = "GPU admin access"
  description  = "Use adminAccess mode: attaches the GPU without consuming it from the allocatable pool. Use when GPU access is infrequent."
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/icon/memory.svg"
  order        = local.workspace_resources_order_start + 6
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Actual Kubernetes resources
provider "kubernetes" {}

# Flux-substituted cluster values (e.g. the public domain) for use in the
# template. See the coder-workspace-cluster-info ConfigMap.
data "kubernetes_config_map" "cluster_info" {
  metadata {
    name      = "coder-workspace-cluster-info"
    namespace = local.namespace
  }
}

# Use an external datasource to get a list of available environment variables
locals {
  environment_vars = [
    "KUBE_POD_IP",
    "KUBERNETES_SERVICE_HOST",
    "KUBERNETES_SERVICE_PORT_HTTPS",
  ]

  environment_vars_escaped_json = "{ ${join(", ", [for environment_var in local.environment_vars : format("\\\"%[1]s\\\": \\\"$${%[1]s}\\\"", environment_var)])} }"
}

data "external" "env" {
  program = ["sh", "-c", "echo \"${local.environment_vars_escaped_json}\""]
}

locals {
  is_in_cluster = data.external.env.result["KUBE_POD_IP"] != ""

  enable_gpu       = data.coder_parameter.enable_gpu.value == "true"
  enable_nfs       = data.coder_parameter.enable_nfs.value == "true"
  gpu_admin_access = data.coder_parameter.gpu_admin_access.value == "true"
  gpu_cel_selector = data.coder_parameter.gpu_type.value == "arc-pro" ? "device.attributes[\"gpu.intel.com\"].family == 'Arc Pro'" : "device.attributes[\"gpu.intel.com\"].family == 'Iris Xe'"
}

provider "kubectl" {
  # If running in a pod, use the in-cluster config
  load_config_file       = !local.is_in_cluster
  host                   = local.is_in_cluster ? "https://${data.external.env.result["KUBERNETES_SERVICE_HOST"]}:${data.external.env.result["KUBERNETES_SERVICE_PORT_HTTPS"]}" : null
  cluster_ca_certificate = local.is_in_cluster ? file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt") : null
  token                  = local.is_in_cluster ? file("/var/run/secrets/kubernetes.io/serviceaccount/token") : null
}

resource "kubernetes_persistent_volume_claim" "pvcs" {
  for_each = local.pvcs

  metadata {
    name        = "${local.name}-${each.key}"
    namespace   = local.namespace
    labels      = local.labels
    annotations = local.annotations
  }

  wait_until_bound = false

  spec {
    storage_class_name = local.storage_class
    access_modes       = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${each.value.size_gb}Gi"
      }
    }
  }
}

resource "kubectl_manifest" "deployment" {
  wait              = false
  wait_for_rollout  = true
  server_side_apply = true
  ignore_fields     = ["status"]

  timeouts {
    create = "10m"
  }

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "Deployment"
    metadata = {
      name        = local.name
      namespace   = local.namespace
      labels      = local.labels
      annotations = local.annotations
    }
    spec = {
      # This is how coder knows what resource to delete upon shutdown.
      replicas = data.coder_workspace.me.start_count
      selector = {
        matchLabels = local.labels
      }
      strategy = {
        type = "Recreate"
      }
      template = {
        metadata = {
          labels      = local.labels
          annotations = local.annotations
        }
        spec = merge(
          {
            # User namespace isolation: root (uid 0) inside the container maps to an
            # unprivileged UID on the host, providing VM-equivalent containment without
            # needing Kata when GPU passthrough is required.
            #
            # Kata does NOT support user namespaces ("RuntimeClass handler kata does not
            # support user namespaces"), so the non-GPU/Kata path must run with hostUsers
            # true. NFS likewise rejects userns ("user namespaces are not supported with
            # nfs mounts"). Only the GPU path (runc, no Kata) without NFS gets a userns.
            hostUsers          = !local.enable_gpu || local.enable_nfs
            enableServiceLinks = false
            hostname           = data.coder_workspace.me.name
            securityContext = {
              runAsUser    = local.uid
              runAsGroup   = local.gid
              fsGroup      = local.gid
              runAsNonRoot = true
              # Avoid a recursive chown of the (multi-TB) NFS share on startup.
              # The bulk-pool shares are already owned by gid 1000, so the root
              # gid matches and kubelet skips the recursive ownership change.
              fsGroupChangePolicy = "OnRootMismatch"
            }
            containers = [{
              name            = "dev"
              image           = "codercom/enterprise-base:ubuntu"
              imagePullPolicy = "Always"
              command         = ["sh", "-c", coder_agent.main.init_script]
              env             = [for k, v in local.env_vars : { name = k, value = v }]
              volumeMounts = concat(
                [for k, v in local.pvcs : { name = k, mountPath = v.mount_path }],
                local.enable_nfs ? [{ name = "nfs-bulk-pool", mountPath = local.nfs_mount_path }] : [],
                [{
                  name      = "cluster-pki-root"
                  mountPath = local.cluster_ca_mount_path
                  subPath   = "cluster-pki-root.crt"
                  readOnly  = true
                }]
              )
              resources = merge(
                {
                  limits = local.enable_gpu ? {
                    cpu    = tostring(data.coder_parameter.cpu.value)
                    memory = "${data.coder_parameter.memory.value}Gi"
                    } : {
                    # Kata overhead: the VM is assigned limits+1 CPUs and limits+2Gi memory.
                    # Offset accordingly to get the actually requested amount.
                    cpu    = tostring(tonumber(data.coder_parameter.cpu.value) - 1)
                    memory = "${tonumber(data.coder_parameter.memory.value) - 2}Gi"
                  }
                },
                local.enable_gpu ? { claims = [{ name = "gpu" }] } : {}
              )
              securityContext = {
                privileged = true
                capabilities = {
                  add = ["SYS_ADMIN"]
                }
              }
            }]
            volumes = concat(
              [for k, v in local.pvcs : {
                name = k
                persistentVolumeClaim = {
                  claimName = kubernetes_persistent_volume_claim.pvcs[k].metadata[0].name
                }
              }],
              local.enable_nfs ? [{
                name = "nfs-bulk-pool"
                nfs = {
                  server = local.nfs_address
                  path   = local.nfs_path
                }
              }] : [],
              [{
                name = "cluster-pki-root"
                secret = {
                  secretName = local.cluster_ca_secret
                  items = [{
                    key  = "ca.crt"
                    path = "cluster-pki-root.crt"
                  }]
                }
              }]
            )
            hostAliases = [{
              hostnames = local.blackhole_domains
              ip        = local.blackhole_address
            }]
            affinity = {
              # This affinity attempts to spread out all workspace pods evenly across nodes.
              podAntiAffinity = {
                preferredDuringSchedulingIgnoredDuringExecution = [{
                  weight = 1
                  podAffinityTerm = {
                    topologyKey = "kubernetes.io/hostname"
                    labelSelector = {
                      matchExpressions = [{
                        key      = "app.kubernetes.io/name"
                        operator = "In"
                        values   = ["coder-workspace"]
                      }]
                    }
                  }
                }]
              }
            }
          },
          local.enable_gpu ? {
            resourceClaims = [{
              name                      = "gpu"
              resourceClaimTemplateName = "${local.name}-gpu"
            }]
          } : {},
          local.enable_gpu ? {} : { runtimeClassName = local.runtime_class }
        )
      }
    }
  })
}

# Prevent evictions from disrupting the workspace
resource "kubernetes_pod_disruption_budget_v1" "main" {
  count = data.coder_workspace.me.start_count

  metadata {
    name        = local.name
    namespace   = local.namespace
    labels      = local.labels
    annotations = local.annotations
  }

  spec {
    min_available = 1

    selector {
      match_labels = local.labels
    }
  }
}

# CiliumNetworkPolicy for coder-workspace
resource "kubectl_manifest" "netpol" {
  count             = data.coder_workspace.me.start_count
  server_side_apply = true
  # cilium-operator-generic co-manages parts of .specs (it writes derived policy
  # state back via the status subresource), so a plain SSA update conflicts. Force
  # ownership of the fields we declare; we remain the manager of the policy intent.
  force_conflicts = true
  wait            = true
  ignore_fields   = ["status"]

  yaml_body = yamlencode({
    "apiVersion" = "cilium.io/v2"
    "kind"       = "CiliumNetworkPolicy"
    "metadata" = {
      "name"      = local.name
      "namespace" = local.namespace
      "labels"    = local.labels
    }

    "specs" = [
      {
        "description" = "coder-workspace"
        "endpointSelector" = {
          "matchLabels" = local.labels
        }
        "egress" = [
          # DNS resolution
          {
            "toEndpoints" = [
              {
                "matchLabels" = {
                  "io.kubernetes.pod.namespace"             = "networking"
                  "endpoints.netpols.home.arpa/cluster-dns" = "true"
                }
              }
            ]
            "toPorts" = [
              {
                "ports" = [
                  {
                    "port"     = "53"
                    "protocol" = "UDP"
                  },
                  {
                    "port"     = "53"
                    "protocol" = "TCP"
                  }
                ]
                "rules" = {
                  "dns" = [
                    {
                      "matchPattern" = "*"
                    }
                  ]
                }
              }
            ]
          },

          # To control plane
          {
            "toEndpoints" = [
              {
                "matchLabels" = local.coder_labels
              }
            ]
          },

          # To the internal ingress gateway, where teleport.<public-domain>
          # resolves for in-cluster clients (the gateway TLS-terminates and
          # re-encrypts to the Teleport proxy). Routing via the gateway means
          # tsh works even though it follows the proxy's advertised public_addr.
          # The gateway's own netpol admits in-cluster clients (fromEntities:
          # cluster) on 443, so no extra label is needed on this pod. The gateway
          # IP is in 10.0.0.0/8, which the internet rule below excepts, so this
          # explicit allow is required.
          {
            "toEndpoints" = [
              {
                "matchLabels" = {
                  "io.kubernetes.pod.namespace"            = "networking"
                  "app.kubernetes.io/name"                 = "ingress-gateways"
                  "gateway.networking.k8s.io/gateway-name" = "internal-gateway"
                }
              }
            ]
            "toPorts" = [
              {
                "ports" = [
                  {
                    "port"     = "443"
                    "protocol" = "TCP"
                  }
                ]
              }
            ]
          },

          # To internet to access arbitrary resources
          {
            "toCIDRSet" = [
              {
                "cidr" = "0.0.0.0/0"
                "except" = [
                  "10.0.0.0/8",
                  "172.16.0.0/12",
                  "192.168.0.0/16"
                ]
              }
            ]
          }
        ]

        # From control plane
        "ingress" = [
          {
            "fromEndpoints" = [
              {
                "matchLabels" = local.coder_labels
              }
            ]
          }
        ]
      }
    ]
  })
}
