---
# No $schema: it rejects the templated addresses.
#
# Only rendered for nodes with `bgpMode: talos` (topf.yaml).
#
# Cilium peers with a local Talos BGP instance ("cilium") over a veth instead of
# the routers. The "fabric" instance imports the service routes and advertises
# them to the routers with BFD, so a dead node's routes drop in ~1s instead of
# after the hold timer plus graceful restart.
# Layout follows Talos' Cilium BGP integration test
# (internal/integration/api/bgp_cilium.go). The Talos end of the veth is in a
# VRF so the two ends route like separate hosts. Cilium skips veths without a
# default route, so the veth is not a Cilium datapath device.
#
# Switching a node to `talos`:
#   1. topf apply the node. Cilium moves to the local peer; the fabric sessions
#      stay down until step 2 (the routers still require the TCP-MD5 password,
#      which Talos BGP doesn't support).
#   2. OPNsense FRR: on this node's neighbor, clear the password and enable BFD.
{{- if eq .Node.Data.bgpMode "talos" }}
apiVersion: v1alpha1
kind: VethConfig
name: veth-cilium
up: true
addresses:
  - address: 10.63.255.254/31
peer:
  name: veth-crouter
  up: true
  addresses:
    - address: 10.63.255.255/31
---
apiVersion: v1alpha1
kind: VRFConfig
name: vrf-cilium
table: 89
links:
  - veth-crouter
up: true
---
# Cilium's side. Routes stay in this instance's RIB; "fabric" imports them.
apiVersion: v1alpha1
kind: BGPInstanceConfig
name: cilium
vrf: vrf-cilium
localASN: 64514
routerID: 10.63.255.255
installRoutes: false
neighbors:
  - address: 10.63.255.254
    peerASN: 64515
    passive: true
    holdTime: 9s
---
# Router side. AS 64513 is what the router neighbors expect (formerly Cilium's).
apiVersion: v1alpha1
kind: BGPInstanceConfig
name: fabric
localASN: 64513
routerID: "{{ .Node.IP }}"
# The routers send nothing; the static default route stays authoritative.
installRoutes: false
importRoutes:
  - bgpInstance: cilium
    prefixes:
      - 10.33.0.0/16 # ClusterIPs
      - 10.34.0.0/16 # LoadBalancer pool
neighbors:
  - address: 10.3.0.1
    peerASN: 64512
    holdTime: 9s
    bfd: &bfd
      transmitInterval: 300ms
      receiveInterval: 300ms
      detectMultiplier: 3
  - address: 10.3.0.2
    peerASN: 64512
    holdTime: 9s
    bfd: *bfd
{{- end }}
