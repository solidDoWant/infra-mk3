---
# No $schema: it rejects the templated addresses.
# Previously, this used separate VLANs for Talos traffic and for
# Kubernetes traffic. This worked well for traffic within the same subnet,
# but caused problems with traffic from other subnets. Requests would come
# in via the Kubernetes VLAN, and responses would be sent out via the
# management VLAN. Normally this _could_ work, with the right firewall
# rules, however the major issue was ICMP responses for fragmented packets.
# With path MTU discovery enabled, ICMP responses would get sent back via
# the wrong VLAN, and never make their way back to the correct interface.
# This was likely in part due to how Cilium handles network traffic via
# eBPF programs attached to specific interfaces.
#
# Document order matches what talhelper emitted, so the migration applied
# without a config diff. Talos itself keys documents by kind + name.
apiVersion: v1alpha1
kind: ResolverConfig
nameservers:
  - address: 10.3.0.254
searchDomains:
  disableDefault: false
---
# SFP+ cages (Intel X710) -> the LACP bond.
#
# If these names ever shift, the rename-proof alternative is a hardware
# selector rather than a name. It is deliberately NOT used yet: switching to
# it rewrites bond0 on every node at once, and a network blip on two control
# plane nodes simultaneously costs etcd quorum. Worth doing as its own change,
# one node at a time, while all three are healthy.
#
# The copper RJ45 ports (Realtek RTL8125 + Intel I226-V, enp3s0/enp4s0) are
# cabled to the management VLAN and deliberately left unconfigured.
apiVersion: v1alpha1
kind: BondConfig
name: bond0
links:
  - enp5s0f0np0
  - enp5s0f1np1
bondMode: 802.3ad
miimon: 100
xmitHashPolicy: layer3+4
lacpRate: fast
mtu: 9000
addresses:
  - address: "{{ .Node.IP }}/16"
  - address: "{{ .Node.Data.bondSecondaryAddress }}/32"
routes:
  - gateway: 10.3.0.254
---
# Non-LB VIP address managed by Talos instead of Cilium. Leaving this for now
# in case swapping to Cilium-backed service doesn't work. Every node is a
# control plane node, so this lives in all/.
apiVersion: v1alpha1
kind: Layer2VIPConfig
name: 10.3.254.1
link: bond0
---
apiVersion: v1alpha1
kind: LinkConfig
name: enp5s0f0np0
mtu: 9000
---
apiVersion: v1alpha1
kind: LinkConfig
name: enp5s0f1np1
mtu: 9000
---
# Creates a link-scoped route for the loopback interface, fixing Istio compatibility
# with Cilium eBPF masquerading. This works by sending link-local traffic through
# iptables, instead of eBPF, which is bugged. Not setting a gateway makes these routes
# link-scoped.
# For details, see https://github.com/istio/istio/issues/52208#issuecomment-2488755452
# This attempts to solve the same issue with talos host DNS caching with the same
# approach.
apiVersion: v1alpha1
kind: LinkConfig
name: lo
routes:
  - destination: 169.254.7.127/32
  - destination: 169.254.116.108/32
