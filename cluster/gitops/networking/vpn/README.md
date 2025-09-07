# vpn-gateway

## Overview

This is a massively overengineered way of routing traffic for specific k8s pods out to the internet via VPN tunnels. Here's what this does that similar setups don't:
* Client pods (pods that should send/receive internet traffic via a VPN provider) do not need any sidecars
* Client pods do not need `CAP_NET_ADMIN` or similar capabilities
* Most connections (`1 - 1/N`) will not be dropped when one of `N` VPN gateway pod fails (termination, network failure, etc.)
* Connections will be balanced between multiple exit nodes, resulting in higher overall throughput and less data being leaked if some exit nodes are compromised

The first two benefits are pretty trivial to do without significant overcomplication/overengineering, but the last two are more difficult to solve.

## Table of contents
* [Architecture](#architecture)
  * [Traffic flow](#traffic-flow)
  * [MTU](#mtu)
  * [Subnet addresses](#subnet-addresses)
  * [Client pod intranet subnet routing](#client-pod-intranet-subnet-routing)
  * [Ingress routing and VPN provider port forwarding](#ingress-routing-and-vpn-provider-port-forwarding)
* [Simple alternative](#simple-alternative)


## Architecture

The [node-network-operator](https://github.com/solidDoWant/node-network-operator), [multus-cni](https://github.com/k8snetworkplumbingwg/multus-cni), [whereabouts](https://github.com/k8snetworkplumbingwg/whereabouts),
and the [bridge CNI plugin](https://www.cni.dev/plugins/current/main/bridge/) are used to build networks that specific pods can be attached to. Unlike some primary CNI plugins (like Cilium with eBPF), these networks
support every networking feature that the kernel supports (such as pod route management).

The node-network operator is used to create network bridges on every node in the cluster, as well as VXLAN interfaces to connect each node's bridges. When pods are created, the CRI invokes multus, which in turn
invokes the bridge and whereabouts plugins. These CNI plugins are used to attach a pod to it's node bridge, and handles IP address and route assignment.

![VPN network interfaces](./docs/VPN%20gateway%20interfaces.svg)

### Traffic flow

A series of VPN gateway pods are deployed. Each of these connects to a different VPN endpoint (and potentially different VPN providers). As a result, traffic flowing through different
gateway pods will enter the Internet with different source IP addresses.

Router pods handle forwarding packets from the client pod to VPN gateway pods. The router pods use connection tracking to ensure traffic belonging to a specific flow (e.g. TCP streams)
is always sent to the same VPN gateway, resulting in each packet within a given flow exiting the VPN provider's network with the same source IP. A `conntrackd` container within each 
router pod is used to sync the connection state table between all router pods.

IPVS, managed by a keepalived container within each router pod, is used to load balance traffic between each VPN gateway. It also uses health checks to track which VPN gateways are
available and healthy. The container uses [NAT Routing](https://keepalived.org/doc/load_balancing_techniques.html#virtual-server-via-nat) to ensure that bidirectional traffic flows
through the pod. While direct routing/direct server return would be preferable for performance reasons, it is important for the return traffic to flow through the pod so that the
connection state table is updated.

Clients know which router pod to send traffic to thanks to VRRP, again managed by keepalived. VRRP provides automatic router failover by moving a floating/virtual IP address around
router pods. When the active router pod becomes unavailable, another pod takes the IP address and sends a gratuitous ARP frame to announce the change to client pods. This doesn't
support load balancing the routers, but it does avoid a race condition that can arise with conntrackd when using asymmetric multi-path routing.

Not shown in the previous network interface diagram is a separate pod network that is exclusively connected to the router pod. This is used exclusively for keepalived and conntrackd
traffic between other keepalived and conntrackd pods.

![VPN gateway network flow](./docs/VPN%20gateway%20network%20flow.svg)

### MTU

It's important to get the MTU right on all interfaces. Too small of a MTU will degrade performance, and too large will cause packet fragmentation, degraded performance, and packet
loss. Here are some notes on picking the right MTU for different parts of the network:
* The MTU network attachment definitions for each subnet should be the same.
* Bridge MTUs should be at least as large as the largest interface on the subnet. That is, they should not be the bottleneck.
* The MTU of the interfaces created by the bridge CNI plugin need to be less than or equal to the MTU of the VXLAN interfaces, as these interfaces will carry all the traffic.
* The VXLAN interfaces need to have an MTU that is no more than 50 less than the underlying device's MTU. This is to account for the VXLAN header overhead. If the underlying device
  has an MTU of 1500, then the VXLAN interfaces' MTU should be no more than 1450. For an underlying interface MTU of 9000, the VXLAN MTU can be as large as 8950.
* The interfaces created by the bridge CNI plugin should be no more than the VPN gateway's wireguard interface MTU. This will likely be the limiting factor for the VPN gateway
  network.

### Subnet addresses

The VPN gateway subnet is defined as 192.168.50.0/24. This is fairly arbitrary - any sufficiently large subnet in private IP space would work, provided that it does not collide with
any other subnets that pods are joined to. The gateway subnet address allocation is further split as follows:
* 192.168.50.1 - 192.168.50.239 - this allocates 239 addresses for client pods.
* 192.168.50.240 - 192.168.50.240 - this allocates one addresses as the router VIP address.
* 192.168.50.241 - 192.168.50.247 - this allocates seven addresses for the routers.
* 192.168.50.248 - 192.168.50.254 - this allocates seven addresses for the VPN gateway.

In addition, a separate set of addresses is needed for the VRPP + conntrackd subnet that is used exclusively by the router pods. This subnet is defined as 192.168.51.0/24 (again,
the value is somewhat arbitrary).

### Client pod intranet subnet routing

To avoid needing a `CAP_NET_ADMIN` sidecar pod, client pods routes added that point to the router VIP address. Rather than adding a default (0.0.0.0/0) route pointing to this, all
but the intranet subnet is used. Here 10.0.0.0/8 is used for the intranet (see [the repo's docs](./../../../../docs/network.yaml)), so separate routes are added for each subnet in
`0.0.0.0/0 - 10.0.0.0/8`:

* 0.0.0.0/5
* 8.0.0.0/7
* 11.0.0.0/8
* 12.0.0.0/6
* 16.0.0.0/4
* 32.0.0.0/3
* 64.0.0.0/2
* 128.0.0.0/1

This can be easily computed with:

```shell
cat <<EOF | python -
from netaddr import IPSet, IPNetwork

subset = IPSet(IPNetwork("0.0.0.0/0"))
subset.remove("10.0.0.0/8")

for subnet in subset.iter_cidrs():
    print(f"{{\"dst\": \"{str(subnet)}\"}},")
EOF
```

By excluding the intranet subnet from the added routes, the primary CNI plugin (which should have added a default route) can continue handling this traffic.

### Ingress routing and VPN provider port forwarding

Support for accepting incoming connections via VPN port forwarding is pretty simple. The VPN provider should port forward desired ports to all VPN gateways. If, for example, the
provider supports forwarding three ports, and supports five simultaneous connections, then a total of 15 external IP/port combinations should be forwarded (three per gateway).

When a VPN gateway receives an incoming connection on one of the allocated ports, it masquerades source of the traffic (replacing the source IP with the pod IP), and the destination
with a fixed address. This fixed address is within the load balancer service IP address range. This address is then assigned to one or more services, which point to application pods.
As a result, traffic from anywhere on the internet destined for a forwarded port on any of the gateways ends up being sent to application pods. This approach retains all the benefits
of k8s services at the low cost of two iptables rules per port.

Most VPN providers with port-forwarding support also provide dynamic DNS domain names that resolve to the public IP address of connected gateways. If application services need to
advertise an location that they can be reached on, then they should advertise this domain name. The VPN provider should keep the DNS records up to date as the VPN gateways connect,
disconnect, and reconnect to different VPN tunnel exits. Remote clients can resolve the address, connect to the VPN tunnel exit, and eventually reach application pods.

## Simple alternative

The majority of the complexity of this design comes from supporting multiple VPN tunnel instances. Cutting this down to a single pod decreases the (collective) VPN tunnel availability,
as well as some throughput, but also allows for entirely removing the router pods.

**To implement this**, just deploy this design but leave out anything related to multiple VPN gateway pods, and the router pods. Then just adjust the client network attachment
definition to set the VPN gateway IP address as the default gateway.
