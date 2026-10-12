---
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  cilium.home.arpa/node.bgp-enabled: "true"
  root-ceph.flux.home.arpa/node.cluster-enabled: "true"
  katacontainers.io/kata-runtime: "true"
  # Topology labels should contain the label name in the value to ensure
  # that the value itself is unique
  topology.rook.io/chassis: chassis-{{ .Node.Host }}
  zfs.home.arpa/node.local-storage-enabled: "true"
  cni-plugins.home.arpa/node.general-purpose-plugins-enabled: "true"
annotations:
  zfs.home.arpa/node.pool-drive-matcher: "/dev/disk/by-id/nvme-KINGSTON_SKC3000D2048G_*"
  # Read by the system-upgrade-controller talos plan, which appends the tag.
  talos.home.arpa/installer-image: factory.talos.dev/metal-installer-secureboot/{{ .SchematicID }}
---
apiVersion: v1alpha1
kind: KernelModuleConfig
name: zfs
