# The per-workspace root disk. CDI imports the base image (local.vm_root_image)
# into this block PVC; the guest grows root to fill it (boot.growPartition +
# fileSystems."/".autoResize). RWX block keeps the VM live-migratable.
#
# This is a STANDALONE Terraform resource - not a spec.dataVolumeTemplates entry -
# on purpose: its name is keyed on the image version (local.root_dv_name), so a
# base-image bump makes Terraform recreate it (new DV imported, OLD DV destroyed,
# no orphaned PVC), and a workspace delete destroys it alongside the VM. A
# dataVolumeTemplate would instead be pruned only on VM deletion, leaking the old
# PVC on every upgrade.
#
# create_before_destroy so the new root finishes importing before the old is
# removed. The VM depends_on this, and base-image upgrades are applied by Updating
# the workspace to a new template version while it is STOPPED (Stop -> Update ->
# Start), so the old root PVC is unmounted by the time Terraform destroys it.
resource "kubectl_manifest" "root_datavolume" {
  server_side_apply = true
  force_conflicts   = true
  wait              = false
  ignore_fields     = ["status"]

  lifecycle {
    create_before_destroy = true
  }

  yaml_body = yamlencode({
    apiVersion = "cdi.kubevirt.io/v1beta1"
    kind       = "DataVolume"
    metadata = {
      name        = local.root_dv_name
      namespace   = local.namespace
      labels      = local.labels
      annotations = local.annotations
    }
    spec = {
      source = {
        registry = {
          url = "docker://${local.vm_root_image}"
          # node pullMethod pulls via the node's container runtime, reusing the
          # dockerconfigjson Harbor secret (the CDI importer pod is not otherwise
          # authorized). Registry import reads the /disk/*.qcow2 from the image.
          pullMethod = "node"
          secretRef  = local.image_pull_secret
        }
      }
      storage = {
        accessModes      = ["ReadWriteMany"]
        volumeMode       = "Block"
        storageClassName = local.storage_class
        resources = {
          requests = {
            storage = "${data.coder_parameter.root_disk_size.value}Gi"
          }
        }
      }
    }
  })
}

# The workspace VirtualMachine.
#
# Lifecycle: runStrategy follows the Coder start_count - "Always" while the
# workspace is started, "Halted" when stopped (VMI powered off, the persistent
# PVC retained). Deleting the workspace destroys this resource (and the PVC).
#
# Storage: a per-workspace root DataVolume (CDI imports local.vm_root_image into
# a block PVC sized by the root_disk_size parameter; the guest grows root to fill
# it) plus the single persistent block PVC. The NixOS image formats the
# persistent disk on first boot and uses it (via impermanence) to back
# /home/coder, /workspace, and the /nix/store overlay. The root is disposable -
# durable state lives on the persistent disk - so a base-image upgrade just
# recreates the root DataVolume (see local.root_dv_name / ./nix).
#
# Networking: local.labels are set on spec.template.metadata.labels and so
# propagate to the virt-launcher pod, which the CiliumNetworkPolicy in
# kubernetes.tf selects. masquerade networking (cluster default) NATs guest
# traffic out the launcher pod IP, so the VM behaves like a normal pod.
resource "kubectl_manifest" "vm" {
  # The root DataVolume must exist (and, on a version bump, the new one must be
  # created) before the VM references it; virt-controller then waits for the DV
  # to finish importing before it boots the VMI.
  depends_on = [kubectl_manifest.root_datavolume]

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
              # The standalone per-workspace root DataVolume
              # (kubectl_manifest.root_datavolume, CDI-imported from
              # local.vm_root_image). virt-controller waits for it to import
              # before booting the VMI.
              dataVolume = {
                name = local.root_dv_name
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
