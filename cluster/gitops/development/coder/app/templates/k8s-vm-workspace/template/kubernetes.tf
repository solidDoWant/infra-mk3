# This block should define all high-level configuration for the deployment.
locals {
  namespace     = "development"
  storage_class = "ssd-replicated-3x"

  labels = {
    # NOTE: app.kubernetes.io/name MUST be "coder-workspace": the
    # restrict-coder-netpol-access Kyverno ClusterPolicy only lets the Coder
    # provisioner SA manage CiliumNetworkPolicies carrying that exact label. The
    # per-workspace instance/id labels below keep the netpol selector unique.
    "app.kubernetes.io/name"     = "coder-workspace"
    "app.kubernetes.io/instance" = "coder-vm-workspace-${data.coder_workspace.me.id}"
    "app.kubernetes.io/part-of"  = "coder"
    "com.coder.resource"         = "true"
    "com.coder.workspace.id"     = data.coder_workspace.me.id
    "com.coder.workspace.name"   = data.coder_workspace.me.name
    "com.coder.user.id"          = data.coder_workspace_owner.me.id
    "com.coder.user.username"    = data.coder_workspace_owner.me.name
  }

  annotations = {
    "com.coder.user.email" = data.coder_workspace_owner.me.email
    # k8tz injects a timezone init container / env; the VM manages its own clock,
    # and (as in the container template) the injection conflicts with the image.
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

  # Cluster PKI root CA. Mounted into the VM via virtiofs (from this secret) at
  # /mnt/root-ca; the NixOS image (see nix/.../modules/ca-trust) builds a combined
  # system+cluster bundle at boot and points the system at it. NODE_EXTRA_CA_CERTS
  # is additive for node tooling, so it points at the cluster cert directly.
  cluster_ca_secret    = "root-ca-pub-cert"
  cluster_ca_cert_path = "/mnt/root-ca/ca.crt"

  # Public domain (SECRET_PUBLIC_DOMAIN_NAME), read from the Flux-substituted
  # coder-workspace-cluster-info ConfigMap. The template files are pushed
  # out-of-band so they never see Flux substitution, and the coder access_url is
  # the internal service URL (coder.development.svc.cluster.local), not the
  # public domain. teleport.<public-domain> resolves to the internal ingress
  # gateway (allowed by the netpol egress rule below).
  public_domain  = data.kubernetes_config_map.cluster_info.data["public_domain_name"]
  teleport_proxy = "teleport.${local.public_domain}:443"

  # The NixOS workspace base image, built and pushed to Harbor by ./nix (see the
  # Makefile there). Used as the VM's ephemeral containerDisk root.
  vm_root_image = "harbor.${local.public_domain}/coder/nixos-workspace:latest"

  # dockerconfigjson secret (development ns) KubeVirt uses to pull the private
  # containerDisk image from Harbor.
  image_pull_secret = "coder-pull-credentials"

  # ServiceAccount projected into the VM for the Teleport kubernetes join. It is
  # Flux-managed (created once, see coder/app/teleport-vm-workspace.yaml) and
  # authorized by the matching TeleportProvisionToken; the template only mounts
  # it. Not created here - per-workspace creation would race and conflict.
  teleport_service_account = "coder-vm-workspace"

  env_vars = {
    CODER_TELEMETRY_ENABLE = "false"
    CODER_AGENT_TOKEN      = coder_agent.main.token
    # The agent is the nixpkgs `coder` binary baked into the image, run directly
    # by the coder-agent systemd unit, so it needs the server URL explicitly
    # (the download-script flow embedded it instead).
    CODER_AGENT_URL                  = data.coder_workspace.me.access_url
    CODER_DERP_SERVER_STUN_ADDRESSES = "disable"
    # Node does not consult the system trust store; point it at the mounted CA so
    # node-based tooling (e.g. Claude Code) also trusts the cluster PKI root.
    NODE_EXTRA_CA_CERTS = local.cluster_ca_cert_path
    # Default the Teleport proxy so `tsh login` works with no flags.
    TELEPORT_PROXY = local.teleport_proxy
  }

  # Guest mount paths surfaced to the Coder agent for disk-usage metadata and
  # monitoring. Both live on the single persistent disk via the NixOS
  # impermanence config (see ./nix); these are just the in-guest paths.
  monitored_volumes = {
    home      = { mount_path = "/home/coder" }
    workspace = { mount_path = "/workspace" }
  }

  name = "coder-vm-workspace-${data.coder_workspace.me.id}"

  coder_labels = {
    "app.kubernetes.io/name"     = "coder"
    "app.kubernetes.io/part-of"  = "coder"
    "app.kubernetes.io/instance" = "coder"
  }
}

# Parameters
locals {
  workspace_resources_order_start = local.claude_order_start + local.claude_size
  workspace_resources_size        = 4
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of vCPUs available to the VM"
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
  description  = "The amount of memory available to the VM in GB"
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

data "coder_parameter" "persistent_disk_size" {
  name         = "persistent_disk_size"
  display_name = "Persistent disk size"
  description  = "Size of the single persistent disk (GB) backing /home/coder, /workspace, and the /nix/store overlay. The system root is ephemeral and reset from the image on every boot."
  default      = "30"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = true
  order        = local.workspace_resources_order_start + 2

  validation {
    min       = 10
    max       = 200
    monotonic = "increasing"
  }
}

data "coder_parameter" "enable_nfs" {
  name         = "enable_nfs"
  display_name = "Mount NFS storage"
  description  = "Mount the bulk-pool-01 NFS storage (all shares) at ${local.nfs_mount_path}"
  type         = "bool"
  default      = "false"
  mutable      = true
  icon         = "/emojis/1f4c1.png"
  order        = local.workspace_resources_order_start + 3
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

  enable_nfs = data.coder_parameter.enable_nfs.value == "true"
}

provider "kubectl" {
  # If running in a pod, use the in-cluster config
  load_config_file       = !local.is_in_cluster
  host                   = local.is_in_cluster ? "https://${data.external.env.result["KUBERNETES_SERVICE_HOST"]}:${data.external.env.result["KUBERNETES_SERVICE_PORT_HTTPS"]}" : null
  cluster_ca_certificate = local.is_in_cluster ? file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt") : null
  token                  = local.is_in_cluster ? file("/var/run/secrets/kubernetes.io/serviceaccount/token") : null
}

# Single persistent disk backing all in-guest user data. Block volume mode so the
# guest gets a raw virtio disk it formats itself; RWX so the VM stays
# live-migratable (RWO would pin the VMI to one node). RBD (ssd-replicated-3x)
# supports RWX in raw-block mode, and only one VMI mounts the filesystem at a
# time, so there is no concurrent-writer hazard.
resource "kubernetes_persistent_volume_claim" "persistent" {
  metadata {
    name        = "${local.name}-persistent"
    namespace   = local.namespace
    labels      = local.labels
    annotations = local.annotations
  }

  wait_until_bound = false

  spec {
    storage_class_name = local.storage_class
    access_modes       = ["ReadWriteMany"]
    volume_mode        = "Block"
    resources {
      requests = {
        storage = "${data.coder_parameter.persistent_disk_size.value}Gi"
      }
    }
  }
}

# CiliumNetworkPolicy for the workspace. The endpointSelector matches local.labels,
# which are set on the VirtualMachine's spec.template.metadata.labels and so
# propagate to the virt-launcher pod - masquerade networking makes the VM behave
# like a normal pod, so the same egress/ingress rules apply unchanged.
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
        "description" = "coder-vm-workspace"
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

          # To the Teleport cluster proxy (ClusterIP, security namespace) for the
          # in-cluster node join + reverse tunnel. The proxy service :443 lands on
          # the proxy pod's :3080. This is the direct path the in-guest Teleport
          # node uses (proxy_server=teleport-cluster.security.svc:443); the
          # ClusterIP is in 10.0.0.0/8, excepted from the internet rule below, so
          # this explicit allow is required.
          {
            "toEndpoints" = [
              {
                "matchLabels" = {
                  "io.kubernetes.pod.namespace" = "security"
                  "app.kubernetes.io/name"      = "teleport-cluster"
                  "app.kubernetes.io/instance"  = "teleport-cluster"
                  "app.kubernetes.io/component" = "proxy"
                }
              }
            ]
            "toPorts" = [
              {
                "ports" = [
                  {
                    "port"     = "3080"
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
