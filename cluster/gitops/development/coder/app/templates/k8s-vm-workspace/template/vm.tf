# The workspace VirtualMachine.
#
# Lifecycle: runStrategy follows the Coder start_count - "Always" while the
# workspace is started, "Halted" when stopped (VMI powered off, the persistent
# PVC retained). Deleting the workspace destroys this resource (and the PVC).
#
# Storage: an ephemeral containerDisk root from the NixOS image
# (local.vm_root_image) plus the single persistent block PVC. The NixOS image
# formats the persistent disk on first boot and uses it (via impermanence) to
# back /home/coder, /workspace, and the /nix/store overlay - so base-image
# updates are an instant tag bump with user data intact (see ./nix).
#
# Networking: local.labels are set on spec.template.metadata.labels and so
# propagate to the virt-launcher pod, which the CiliumNetworkPolicy in
# kubernetes.tf selects. masquerade networking (cluster default) NATs guest
# traffic out the launcher pod IP, so the VM behaves like a normal pod.
resource "kubectl_manifest" "vm" {
  server_side_apply = true
  # KubeVirt's virt-api co-owns .spec.runStrategy (it writes it back when
  # processing start/stop), but this template is the intended owner - it drives
  # runStrategy from the Coder start_count. Without forcing, the start/stop apply
  # fails with an SSA field-manager conflict on runStrategy.
  force_conflicts = true
  wait            = false
  ignore_fields   = ["status"]

  timeouts {
    create = "10m"
  }

  yaml_body = yamlencode({
    apiVersion = "kubevirt.io/v1"
    kind       = "VirtualMachine"
    metadata = {
      name        = local.name
      namespace   = local.namespace
      labels      = local.labels
      annotations = local.annotations
    }
    spec = {
      # Start/stop driven by Coder. Halted retains the persistent disk.
      runStrategy = data.coder_workspace.me.start_count == 1 ? "Always" : "Halted"

      template = {
        metadata = {
          # Load-bearing: these propagate to the virt-launcher pod so the
          # CiliumNetworkPolicy endpointSelector matches it.
          labels      = local.labels
          annotations = local.annotations
        }
        spec = {
          # RWX block disks are migratable, so let the cluster live-migrate the
          # workspace off a draining node instead of killing it. virt-controller
          # auto-manages a PodDisruptionBudget for migratable VMs, so no manual
          # PDB is needed.
          evictionStrategy = "LiveMigrate"

          domain = {
            cpu = {
              sockets = tonumber(data.coder_parameter.cpu.value)
              cores   = 1
              threads = 1
            }
            memory = {
              guest = "${data.coder_parameter.memory.value}Gi"
            }
            resources = {
              requests = {
                cpu    = tostring(data.coder_parameter.cpu.value)
                memory = "${data.coder_parameter.memory.value}Gi"
              }
              limits = {
                memory = "${data.coder_parameter.memory.value}Gi"
              }
            }
            devices = {
              disks = [
                {
                  name      = "rootfs"
                  bootOrder = 1
                  disk      = { bus = "virtio" }
                },
                {
                  name = "persistent"
                  # Stable identifier so the guest can find this disk regardless
                  # of probe order: surfaces as /dev/disk/by-id/virtio-persistent.
                  serial = "persistent"
                  disk   = { bus = "virtio" }
                },
                {
                  name = "cloudinit"
                  disk = { bus = "virtio" }
                }
              ]
              filesystems = [
                {
                  # Cluster PKI root CA; the guest builds a combined trust bundle
                  # from it at boot (see nix/.../modules/ca-trust).
                  name     = "root-ca"
                  virtiofs = {}
                },
                {
                  # Kubernetes ServiceAccount token, read by Teleport (via the
                  # in-guest bindfs workaround) to join the cluster as a node.
                  name     = "serviceaccount"
                  virtiofs = {}
                }
              ]
              interfaces = [
                {
                  name       = "default"
                  masquerade = {}
                }
              ]
            }
          }

          networks = [
            {
              name = "default"
              pod  = {}
            }
          ]

          volumes = [
            {
              name = "rootfs"
              containerDisk = {
                image           = local.vm_root_image
                imagePullPolicy = "Always"
                # The image lives in a private Harbor project; KubeVirt pulls the
                # containerDisk with this dockerconfigjson secret (development ns).
                imagePullSecret = local.image_pull_secret
              }
            },
            {
              name = "persistent"
              persistentVolumeClaim = {
                claimName = kubernetes_persistent_volume_claim.persistent.metadata[0].name
              }
            },
            {
              name = "root-ca"
              secret = {
                secretName = local.cluster_ca_secret
              }
            },
            {
              # The workspace ServiceAccount, projected into the guest for the
              # Teleport kubernetes join (token allows development:coder-vm-workspace).
              name = "serviceaccount"
              serviceAccount = {
                serviceAccountName = local.teleport_service_account
              }
            },
            {
              name = "cloudinit"
              cloudInitNoCloud = {
                userData = templatefile("${path.module}/cloud-init.yaml.tftpl", {
                  HOSTNAME = data.coder_workspace.me.name
                  # base64 to sidestep YAML escaping of the env file values. The
                  # agent binary itself is baked into the image (pkgs.coder); only
                  # its environment (token, URL, CA, etc.) is supplied per-workspace.
                  AGENT_ENV_B64  = base64encode(join("\n", [for k, v in local.env_vars : "${k}=${v}"]))
                  ENABLE_NFS     = local.enable_nfs
                  NFS_ADDRESS    = local.nfs_address
                  NFS_PATH       = local.nfs_path
                  NFS_MOUNT_PATH = local.nfs_mount_path
                })
              }
            }
          ]

          # Spread workspace VMs across nodes.
          affinity = {
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
        }
      }
    }
  })
}
