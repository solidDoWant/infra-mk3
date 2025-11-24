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

  env_vars = {
    CODER_TELEMETRY_ENABLE           = "false"
    CODER_AGENT_TOKEN                = coder_agent.main.token
    CODER_DERP_SERVER_STUN_ADDRESSES = "disable"
  }

  pvcs = {
    home = {
      size_gb    = data.coder_parameter.home_disk_size.value
      mount_path = "/home/coder"
    }

    workspace = {
      size_gb    = data.coder_parameter.workspace_disk_size.value
      mount_path = "/workspace"
    }
  }

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
  workspace_resources_order_start = local.mcp_order_start + local.mcp_size
  workspace_resources_size        = 4
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
    max = 8
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

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Actual Kubernetes resources
provider "kubernetes" {}

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

resource "kubernetes_service_account" "workspace" {
  count = local.mcp_kubernetes_enabled ? 1 : 0

  metadata {
    name        = local.name
    namespace   = local.namespace
    labels      = local.labels
    annotations = local.annotations
  }
}

resource "kubernetes_deployment" "main" {
  wait_for_rollout = false

  metadata {
    name        = local.name
    namespace   = local.namespace
    labels      = local.labels
    annotations = local.annotations
  }

  spec {
    # This is how coder knows what resource to delete upon shutdown.
    replicas = data.coder_workspace.me.start_count

    selector {
      match_labels = local.labels
    }

    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels      = local.labels
        annotations = local.annotations
      }

      spec {
        service_account_name = local.mcp_kubernetes_enabled ? kubernetes_service_account.workspace[0].metadata[0].name : null

        runtime_class_name = local.runtime_class

        security_context {
          run_as_user     = local.uid
          run_as_group    = local.gid
          fs_group        = local.gid
          run_as_non_root = true
        }

        container {
          name              = "dev"
          image             = "codercom/enterprise-base:ubuntu"
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]

          dynamic "env" {
            for_each = local.env_vars
            content {
              name  = env.key
              value = env.value
            }
          }

          dynamic "volume_mount" {
            for_each = local.pvcs
            content {
              name       = volume_mount.key
              mount_path = volume_mount.value.mount_path
            }
          }

          resources {
            # The limits are what actually matters with kata containers. This determines how many
            # CPUs and how much memory the VM gets.
            limits = {
              # For some weird reason that is very vaguely alluded to in some of the kata container docs
              # and issues, it will assign the number of CPUs as limits + 1, and memory as limits + 2Gi.
              # Offset accordingly to get the actually specified amount.
              cpu    = tonumber(data.coder_parameter.cpu.value) - 1
              memory = "${tonumber(data.coder_parameter.memory.value) - 2}Gi"
            }
          }

          security_context {
            privileged = true
            capabilities {
              add = [
                "SYS_ADMIN"
              ]
            }
          }
        }

        dynamic "volume" {
          for_each = local.pvcs
          content {
            name = volume.key
            persistent_volume_claim {
              claim_name = kubernetes_persistent_volume_claim.pvcs[volume.key].metadata[0].name
            }
          }
        }

        host_aliases {
          hostnames = local.blackhole_domains
          ip        = local.blackhole_address
        }

        # This is just noise
        enable_service_links = false
        hostname             = data.coder_workspace.me.name

        affinity {
          // This affinity attempts to spread out all workspace pods evenly across
          // nodes.
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values = [
                      "coder-workspace"
                    ]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

# CiliumNetworkPolicy for coder-workspace
resource "kubectl_manifest" "netpol" {
  count             = data.coder_workspace.me.start_count
  server_side_apply = true
  wait              = true

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
