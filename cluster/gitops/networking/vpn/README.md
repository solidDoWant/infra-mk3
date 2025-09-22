# vpn-gateway

## Overview

> [!TIP]
> Click [here](#simple-alternative) if you don't care about the details and just want something simple that works.

This is a massively over-engineered way of routing traffic for specific k8s pods ti and from the internet via VPN tunnels. Here's what this does that similar setups don't:
* Client pods (pods that should send/receive internet traffic via a VPN provider) do not need any sidecars
* Client pods do not need `CAP_NET_ADMIN` or similar capabilities
* Client pods can be configured to accept VPN ingress traffic via a single annotation
* Most connections (`1 - 1/N`) will not be dropped when one of `N` VPN gateway pod fails (termination, network failure, etc.)
* Egress _and_ ingress connections will be load balanced between multiple exit nodes, resulting in significantly higher overall throughput and less data being leaked if some exit nodes are compromised

The first two benefits are pretty easy to do without significant over-complication/over-engineering, but the rest are more difficult to solve.

## Table of contents
* [vpn-gateway](#vpn-gateway)
  * [Overview](#overview)
  * [Table of contents](#table-of-contents)
  * [Definitions](#definitions)
  * [What's hard and what's easy](#whats-hard-and-whats-easy)
  * [Architecture](#architecture)
    * [Traffic flow](#traffic-flow)
      * [Egress traffic flow](#egress-traffic-flow)
      * [Ingress traffic flow](#ingress-traffic-flow)
    * [MTU](#mtu)
    * [Subnet addresses](#subnet-addresses)
    * [Client pod intranet subnet routing](#client-pod-intranet-subnet-routing)
    * [DNS resolution](#dns-resolution)
    * [Ingress/remote client IP address resolution/DDNS](#ingressremote-client-ip-address-resolutionddns)
  * [Example to show that this works](#example-to-show-that-this-works)
    * [Egress traffic](#egress-traffic)
    * [Ingress traffic](#ingress-traffic)
  * [Simple alternative](#simple-alternative)
    * [Example simple setup](#example-simple-setup)
    * [Ingress routing and VPN provider port forwarding](#ingress-routing-and-vpn-provider-port-forwarding)

## Definitions

Here are a few terms that I'll use throughout this document that need a clear definition:
* **VPN (gateway) network** - a network that specific pods can join for the purpose of sending/receiving internet traffic via a VPN tunnel.
* **Client pod** - an application pod that wishes to send and/or receive traffic from the Internet via a VPN. This is a "client" of the VPN network.
* Remote service/client - a server or client that exists somewhere on the Internet.
* **Egress traffic** - a traffic flow _originating_ from a client pod that is destined for a remote service. An example of this would be a client pod attempting to download a file via HTTP,
  so the client initiates the flow by sending a `TCP SYN` packet to the remote service. After the first packet is sent by the client pod, the remote service can send traffic (e.g.
  `TCP SYN-ACK` packet) back to the client pod.
* **Ingress traffic** - a traffic flow _originating_ from a remote client that is destined for a client pod. An example of this would be a remote service attempting to download a file from
  a self-hosted service that is accessible via a VPN tunnel. This is the exact opposite of egress traffic.
* **Gateway** - a service that provides access to another network, typically the Internet. This will have an IP address on both networks. It will perform _source network address translation_
  (SNAT) for egress traffic, and _destination network address translation_ (DNAT) for ingress traffic. This is needed when crossing the network boundary so that incoming (egress return
  and ingress source) packets get sent to the correct destination.
* **Gateway pod** - a gateway that exists within a k8s pod. This provides internet access to pods within the VPN network via a VPN tunnel. Each instance of a gateway pod will have a separate
  public (Internet) IP address.
* **Router** - a service that determines where a packet should be sent to next. This is _usually_ done purely based off of destination IP address with rules that say, for example, "send all
  traffic destined for 1.2.3.4 to the next router at 5.6.7.8 via interface eth0". However, routing rules can also take into account other packet properties such as "firewall marks".
* **Router pod** - a router that exists within a k8s pod. Pods within the VPN network use router pods to determine where bidirectional traffic should be sent. These pods also contain L4
  load balancers, though this could be separated out into another set of pods if there was a technical benefit to doing so.
* **Virtual IP (VIP) address** - an IP address that can move between different interfaces/pods on a network. This is generally used to facilitate failover.

## What's hard and what's easy

As mentioned above, this setup is pretty complex. There are several feature subsets of this setup can be added/removed from this project to balance complexity with features:

| Setup                                                | Complexity | Details                                                                                                                                                                       |
| ---------------------------------------------------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| VPN sidecar per app pod                              | Trivial    | Just add gluetun as a sidecar container. This is super simple if only one pod is deployed, but becomes harder to maintain (and more expensive) the more pods need VPN access. |
| VPN network with a single VPN gateway                | Low        | This involves deploying a network (physical, VLAN, VXLAN, etc.) that app or "client pods" connect to, with a single gluetun "gateway" pod for VPN traffic.                    |
| VPN network, single gateway, easy pod DNS            | High       | Same as above, but also requires deploying additional DNS resolvers, keepalived and iptables rules. Removes the need to set `dnsPolicy` and `dnsConfig` on every client pod.  |
| VPN network, single gateway, ingress                 | Moderate   | Same as VPN network with a single gateway, but also requires an init container with a couple of simple iptables rules.                                                        |
| VPN network, single gateway, ingress, load balancing | High       | Same as VPN network + ingress, but also needs keepalived for VRRP and IPVS management. This builds something akin to k8s services from scratch.                               |
| VPN network with multiple egress-only VPN gateways   | High       | Requires VPN network as well as keepalived + gateway route monitor pods with specific sysctls. Greatly increases egress/download performance, and reduces impact of downtime. |
| VPN network, multiple gateways, egress + ingress, LB | This setup | Same as above, but also special connection tracking and routing configuration. Optionally supports DDNS management for multiple gateway/ingress IP addresses.                 |

## Architecture

The [node-network-operator](https://github.com/solidDoWant/node-network-operator), [multus-cni](https://github.com/k8snetworkplumbingwg/multus-cni), [whereabouts IPAM plugin](https://github.com/k8snetworkplumbingwg/whereabouts),
and [bridge CNI plugin](https://www.cni.dev/plugins/current/main/bridge/) are used to build networks that specific pods can be attached to. Unlike some primary CNI plugins (like Cilium with eBPF), these networks
support every networking feature that the kernel supports (such as route and IPVS management).

The node-network operator is used to create network bridges on every node in the cluster, as well as VXLAN interfaces to connect each node's bridges. When pods are created, the CRI invokes multus, which in turn
invokes the bridge and whereabouts plugins. These CNI plugins are used to attach a pod to it's node bridge, and handles IP address and route assignment.

> [!NOTE]
> While node-network-operator is used here to deploy the bridge and VXLAN interfaces, they could be deployed outside of k8s via "typical" network management tools such as iproute2,
> Talos machine config, Network Manager, etc.

> [!NOTE]
> While a VXLAN is used here, any other type of network (physical device, VLAN, VLAN-in-VLAN P2P tunnels) could be used provided that it connects the bridges on all nodes. I chose a VXLAN
> because it's pretty simple to set up, and other network devices (e.g. physical switches) don't need to know about it to switch traffic properly.

![VPN gateway network interfaces](./docs/VPN%20gateway%20interfaces.svg)

### Traffic flow

Egress and ingress traffic are handled very differently due to a by-design limitation in how the Linux kernel handles routing. However, the core components of the architecture are the
same for both of them.

#### Egress traffic flow

A series of VPN gateway pods are deployed using [gluetun](https://github.com/qdm12/gluetun). Each of these connects to a different VPN endpoint (and potentially different VPN providers).
As a result, traffic flowing through different gateway pods will enter the Internet with different source IP addresses. For remote services, these look like completely separate clients, 
even if a single client application is establishing multiple connections at once to the same service.

Router pods handle forwarding packets from the client pod to VPN gateway pods. The router pods use ECMP hashing to ensure traffic belonging to a specific flow (e.g. TCP streams) is 
always sent to the same VPN gateway, resulting in each packet within a given flow exiting the VPN provider's network with the same source IP. Several sysctls are needed for the pod to
configure which fields should be hashed, and to set a static hash seed value that is the same for all nodes. **This approach does not require syncing connection state** between router
pods, which both avoids the need for connection table syncing, and allows for direct server return.

Routes within the router pod are updated automatically via [gateway-route-manager](https://github.com/solidDoWant/gateway-route-manager). This checks each gateway's health every second,
and updates the pod's routing table so that the default route exclusively contains all available gateways as ECMP nexthops. For each gateway, these checks verify that gluetun is available
and that it reports that the tunnel is healthy.

Clients know which router pod to send traffic to thanks to VRRP, managed by [keepalived](https://keepalived.org/). VRRP provides automatic router failover by moving a VIP address around
router pods. When the active router pod becomes unavailable, another pod takes the IP address and sends a gratuitous ARP frame to announce the change to client pods. Unfortunately while
this doesn't support load balancing across the routers, it does provide high availability. **This approach does not require client pods to know which gateways are available**.

Not shown in the previous network interface diagram is a separate pod network that is exclusively connected to the router pod. This is used exclusively for VRRP announcement traffic
between the keepalived containers.

![VPN gateway network egress flow](./docs/VPN%20gateway%20network%20flow%20egress.svg)

#### Ingress traffic flow

Ingress traffic flow is much more complex due to one (conceptually) simple issue: Linux routing logic is, by design, stateless. This works great in basically every other network design,
which typically looks like this (simplified):

![Typical ECMP flow](./docs/Typical%20ECMP%20flow.svg)

With this typical design, traffic within a single flow/stream can take multiple paths.

A major problem arises when there are multiple gateways, with multiple addresses, between the server first hop router and the rest of the Internet:

![VPN gateway network ECMP flow](./docs/VPN%20network%20ECMP%20flow.svg)

As soon as there are multiple gateways between the Internet and the rest of the VPN gateway network, return traffic can get SNATed to a different IP address. Clients typically take five
packet properties into account when associating them with a specific flow (connection tracking):
* Source IP address
* Destination IP address
* L4 protocol (e.g. TCP, UDP)
* Source port
* Destination port

> [!NOTE]
> Source and destination are inverted for inbound and outbound packets, but connection tracking automatically takes this into account. When discussing connection tracking, "source" and
> "destination" usually refer to the source and destination as seen by the originator of the flow.

While this response _is_ received by clients, they don't associate it with the original request, because the server's address in the response does not match the flow's recorded destination
address. To ensure that the VPN gateway network router uses the same gateway for all traffic in a given flow, I had to build something to make routing stateful. As previously mentioned, the
kernel does support this out of the box, so I had to build something somewhat hacky to get this to work.

![VPN gateway network ingress flow](./docs/VPN%20gateway%20network%20flow%20ingress.svg)

*Backup router, health checks, VRRP advertisements, and client load balancing not shown*

In addition to the "general" next hop address at 192.168.26.254 that is used by client pods, an VIP address is added for each gateway. The diagram only shows two gateways, but I'm running
several additional gateways which require additional VIPs. Each gateway is configured to DNAT ingress traffic to the gateway-specific VIP on the router. This allows netfilter/iptables rules,
which operator on L3, to tie the packet back to a specific L2 source. For each gateway, the router has an iptables rule that adds a gateway-specific "firewall mark" to the connection. When
the client pod sends outbound (return) traffic, the firewall mark is restored. **This allows outbound traffic to be tied back to the gateway that received the originating traffic**. With the
firewall mark added, mark-specific routing policy rules (i.e. `ip rule`s) rules are used to forward the traffic back to the originating gateway. For the specific commands to set this up, see
[the return routing setup script](./router/scripts/setup-return-routing.sh).

This approach still does not require **any** state synchronization. Upon failover, kernel connection tracking on the newly-activated router will treat inbound packet as new connections, even
for packets (e.g. `TCP ACK`) that don't typically establish a L4 connection (e.g. `TCP SYN`). However, immediately after failover, outbound packets from client pods will likely take the wrong
route (and therefore gateway) until the remote client sends a single inbound packet. In the worst case scenario, remote clients will interpret the failover as a one-off, small amount of
packet loss.

Not covered up to this point is client pod ingress load balancing. When a router receives a DNATed inbound packet destined for one of the router's VIPs, it is pulled out of the network stack
by IPVS. IPVS is configured via keepalived to DNAT this traffic (again) to healthy client pods. Here's what this looks like:

![VPN gateway ingress flow with load balancing](./docs/VPN%20gateway%20network%20flow%20ingress%20load%20balancing.svg)

Keepalived configures a separate virtual server per port/protocol (TCP, UDP) combination [as defined here](./router/scripts/keepalived-conf-gen.sh). These virtual servers listen on the
router's gateway-specific VIP addresses, receiving the inbound traffic that was DNATed by each gateway. This traffic is then DNATed again, destined for real server client pods. Keepalived
also performs health checks to add and remove client pods from the pool of real servers as they become healthy or unhealthy. This is, in essence, how kube-proxy works in IPVS mode.

To avoid needing to sync IPVS state (which associates a connection with a specific real server), two things are needed:
* A connection scheduler that does not require state synchronization.
* The `net.ipv4.vs.sloppy_tcp` sysctl enabled (set to `1`), allowing LVS connections to be re-established mid-TCP stream.

I'm currently using the source hash scheduler, which forwards traffic to real servers based on a hash of the source IP and port. This works adequately, but it doesn't handle changes in real
server state well (that is, adding or removing real servers). To mitigate this, I'll probably switch to the maglev hashing scheduler once [it is enabled for the OS I use,
Talos](https://github.com/siderolabs/pkgs/commit/9ac23925cf350075a4931a54176fdd3d9b9b7cb7). This should be out in the v1.11.2 release, or v1.12.0 at the latest.

### MTU

It's important to get the MTU right on all interfaces. Too small of a MTU will degrade performance, and too large will cause packet fragmentation, degraded performance, and packet
loss. Here are some notes on picking the right MTU for different parts of the network:
* The MTU network attachment definitions for each subnet should be the same.
* Bridge MTUs should be at least as large as the largest interface on the subnet. That is, they should not be the bottleneck.
* The MTU of the interfaces created by the bridge CNI plugin need to be less than or equal to the MTU of the VXLAN interfaces, as these interfaces will carry all the traffic.
* The VXLAN interfaces need to have an MTU that is no more than 50 less than the underlying device's MTU. This is to account for the VXLAN header overhead. If the underlying device
  has an MTU of 1500, then the VXLAN interfaces' MTU should be no more than 1450. For an underlying interface MTU of 9000, the VXLAN MTU can be as large as 8950.
* The interfaces created by the bridge CNI plugin should be no more than the VPN gateway's wireguard interface MTU. This will likely be the limiting factor for the VPN gateway
  network. This can range from 1300 to 1500. The Linux kernel default MTU is 1420 (standard MTU is 1500, and wireguard has an 80 byte overhead).

### Subnet addresses

The VPN gateway subnet is defined as 192.168.24.0/22. This is fairly arbitrary - any sufficiently large subnet in private IP space would work, provided that it does not collide with
any other subnets that pods are joined to. The gateway subnet address allocation is further split as follows:
* For gateways
  * 192.168.25.128/29 - 8 addresses, one per gateway
* For routers
  * 192.168.26.0/25 - 128 addresses, one per router
  * For client pods/outbound as next hop
    * 192.168.26.254 - one address, VIP
  * For each individual gateway as ingress DNAT destination
    * 192.168.26.128/29 - 8 addresses, VIP, one per gateway
* For client pods
  * For DNS
    * 192.168.27.128/30 - 3 addresses, one per pod, excludes last address
  * For port 1..N
    * 192.168.27.{16 * (n - 1)}/28 (e.g. 192.168.27.0/28, 192.168.27.16/28, etc.) - 16 addresses, one per pod
  * For all others
    * 192.168.24.0/24 - 254 addresses, one per pod

The network (192.168.24.0) and broadcast (192.168.27.255) addresses for the complete subnet are excluded from the above ranges, but all other addresses (e.g. 192.168.26.0) are available
for hosts.

In addition, a separate set of addresses is needed for the VRRP advertisements subnet that is used exclusively by the router pods. This subnet is defined as 192.168.28.0/24 (again,
the value is somewhat arbitrary).

### Client pod intranet subnet routing

To avoid needing a `CAP_NET_ADMIN` sidecar pod, client pods routes are added that point to the router VIP address. Rather than adding a default (0.0.0.0/0) route pointing to this, all
but the intranet subnet is used. I'm using 10.0.0.0/8 is for the intranet (see [the repo's docs](./../../../../docs/network.yaml)), so separate routes are added for each subnet in
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

By excluding the intranet subnet from the added routes, the primary CNI plugin (which should have added a default route) can continue handling this traffic. This allows pods attached
to the VPN network to send and receive traffic to and from other cluster pods.

### DNS resolution

The VPN gateway network has a pair of CoreDNS pods deployed to handle DNS resolution. These resolve requests for the `cluster.local` domain name, and forward all other requests to public
resolvers. Because these DNS pods are attached to the VPN network, all lookups they perform go out to the Internet via the VPN gateways, rather than leaking the queries via the cluster's
"normal" DNS resolvers.

By default, all pods in the k8s cluster are configured to forward DNS queries to the DNS resolver at the tenth host address within the cluster's configured ClusterIP subnet (e.g.
10.33.0.10), with the exception of pods with host networking/host network namespace enabled. To ensure that all DNS queries get sent to the VPN DNS resolvers, client pods are configured
to route traffic destined for 10.33.0.10 to the router's 192.168.26.254 VIP. This configuration is handled automatically via the network attachment definition.

The router pods have a pair (TCP, UDP) of virtual servers set up that listen on the VIP for port 53 traffic. Packets destined for this address are then forwarded to healthy DNS resolver
pods, which handle the actual resolution. The DNS pods are configured to route _all_ traffic, rather than switch, so responses go back to the router which "reverts" the DNATing, thus
ensuring that client pod connection tracking for DNS requests works properly.

### Ingress/remote client IP address resolution/DDNS

Every time a gluetun container within the VPN gateway pods is restarted (or the pod is restarted, or rescheduled), it will likely change IP address. To allow remote clients to "discover"
VPN IP addresses to connect to for ingress traffic, they are provided with a domain name to connect to rather than an IP address. The mechanism for informing remote clients of this
address is handled either at the application layer (e.g. bittorrent announcements) or out of band entirely.

DDNS is usually pretty easy, but having multiple VPN ingress gateways (with separate public IP addresses) makes this more complicated (again). Most existing DDNS tooling, if not all, only
supports querying for a single public address, and nearly all DDNS providers only support updating a record with a single address.

To work around these limitations, I added DDNS management support to the (now poorly named) gateway-route-manager. After each health check, the tool queries each gateway's gluetun's control
server for the gateway's public IP address. When the set of public IP addresses changes (either due to a pod becoming available, unavailable, or the wireguard tunnel restarting), the tool
calls the DDNS provider's API to update the DNS record with the new set of IP addresses.

As previously mentioned, finding a DDNS provider that supports this was difficult. I had a few requirements:
* I should be technically able to sign up anonymously
* I should be able to update the DNS record for the DDNS hostname with more than one IP address via API
* I should be able to remove IP addresses for unhealthy gateways via API
* If I need to pay for any of the above, then I need to be able to pay anonymously (e.g. cryptocurrency)

I initially used [ChangeIP](https://www.changeip.com/), but I found that their API doesn't actually support this. There is a bug with their API where if multiple addresses are specified,
any addresses that haven't been specified before are _appended_, and old records are never removed from their nameservers. I talked with their support and it sounds like I'm the first
person to have hit this issue, and they are not currently planning on fixing it. As a side note, I hope they add some check/control around this - I could see a malicious user exploiting
this to load billions of records into their DNS servers, per subdomain.

I landed on [Dynu](http://dynu.com/) for this. While their DDNS update endpoints do not support this, it looks like domains added for DDNS can have their DNS records directly managed via
their API. This works pretty well, but I recently found that I can only specify four records, which limits the number of gateways that I can deploy. I may end up finding another provider
because of this.

## Example to show that this works

### Egress traffic

Here's a simple test to show requests going out via different gateways:

```yaml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: make-requests
spec:
  template:
    metadata:
      annotations:
        k8s.v1.cni.cncf.io/networks: networking/gateway-network-client-pods@vpn-gw-veth0
    spec:
      containers:
        - name: requests
          image: nicolaka/netshoot
          command:
            - bash
            - -c
            - |
              declare -A IP_COUNT
              TOTAL_COUNT=40
              FAILED_COUNT=0

              for I in $(seq 1 "${TOTAL_COUNT}"); do
                IP_ADDRESS="$(curl -fsSL ifconfig.me)"
                if [ $? -ne 0 ]; then
                  echo "Request "${I}" failed"
                  FAILED_COUNT="$((FAILED_COUNT + 1))"
                  continue
                fi

                IP_COUNT[$IP_ADDRESS]="$([[ -n "${IP_COUNT["${IP_ADDRESS}"]}" ]] && echo "$(( IP_COUNT["${IP_ADDRESS}"] + 1 ))" || echo "1")"
              done

              echo "Summary of observed source IP addresses:"
              for IP in "${!IP_COUNT[@]}"; do
                echo "  ${IP}: ${IP_COUNT[$IP]} times"
              done
              echo "Failed requests: ${FAILED_COUNT} ($((FAILED_COUNT * 100 / TOTAL_COUNT))%)"
          securityContext:
            capabilities:
              drop:
                - ALL
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            runAsUser: 1000
            seccompProfile:
              type: RuntimeDefault
      restartPolicy: Never
  ttlSecondsAfterFinished: 120

```

Output (actual exit tunnel addresses omitted):

```console
$ kubectl apply -f /tmp/request-test.yaml 
job.batch/make-requests created
$ kubectl logs jobs/make-requests -c requests
Summary of observed source IP addresses:
  1.0.0.0: 12 times
  2.0.0.0: 14 times
  3.0.0.0: 9 times
  4.0.0.0: 5 times
Failed requests: 0 (0%)
```

> [!NOTE]
> The egress gateway chosen is pseudo-random, dependent on the source port chosen. If there is a correlation between chosen port and part of this test (for example, the time between
> requests), then the results will be skewed.

I've done some throughput testing as well via [Linux ISO torrents](https://distrowatch.com/dwres.php?resource=bittorrent). Download speed seems to scale linearly with number of gateways
deployed. At four gateways deployed and a single well-seeded torrent, the bottleneck becomes my (underlying, non-VPN) gigabit Internet connection. I'm typically able to hit ~800 Mbps within
~5 seconds of starting a download. I'm not sure if this is bypassing my VPN provider's per-tunnel bandwidth limit, or seeder's per-IP bandwidth limit, or both.

### Ingress traffic

Here's a simple "echo" service that will be accessible via the VPN gateways:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vpn-ingress-traffic
spec:
  selector:
    matchLabels:
      app: vpn-ingress-traffic
  template:
    metadata:
      labels:
        app: vpn-ingress-traffic
      annotations:
        k8s.v1.cni.cncf.io/networks: networking/gateway-network-client-pods-forwarded-port-2@vpn-gw-veth0
    spec:
      containers:
        - name: vpn-ingress-traffic
          image: mendhak/http-https-echo:37
          env:
            - name: HTTP_PORT
              value: "${SECRET_VPN_FORWARDED_PORT_2}"
          securityContext:
            capabilities:
              drop:
                - ALL
            allowPrivilegeEscalation: false
            runAsNonRoot: true
            runAsUser: 1000
            seccompProfile:
              type: RuntimeDefault
```

Here are some requests made against the service (some details omitted or replaced):
<!-- cSpell:disable -->
```console
$ kubectl apply -f /tmp/response-test.yaml 
deployment.apps/vpn-ingress-traffic created
$ curl ${SECRET_VPN_DDNS_HOSTNAME}$:${SECRET_VPN_FORWARDED_PORT_2}
{
  "path": "/",
  "headers": {
    "host": "${SECRET_VPN_DDNS_HOSTNAME}$:${SECRET_VPN_FORWARDED_PORT_2}",
    "user-agent": "curl/8.5.0",
    "accept": "*/*"
  },
  "method": "GET",
  "body": "",
  "fresh": false,
  "hostname": "${SECRET_VPN_DDNS_HOSTNAME}$",
  "ip": "1.2.3.4",  # My real non-VPN public address
  "ips": [],
  "protocol": "http",
  "query": {},
  "subdomains": [
    "my-ddns-subdomain"
  ],
  "xhr": false,
  "os": {
    "hostname": "vpn-ingress-traffic-845cdfc46c-nk8gk"
  },
  "connection": {}
}
# Delete the pod to show automatic failover to its replacement
$ kubectl delete pod vpn-ingress-traffic-d74d8dd44-sdxc4 
pod "vpn-ingress-traffic-d74d8dd44-sdxc4" deleted
$ curl -s ${SECRET_VPN_DDNS_HOSTNAME}$:${SECRET_VPN_FORWARDED_PORT_2} | jq -r '.os.hostname'
vpn-ingress-traffic-845cdfc46c-tdrjs
```
<!-- cSpell:enable -->

## Simple alternative

The majority of the complexity of this design comes from supporting multiple VPN tunnel instances. Cutting this down to a single pod decreases the (collective) VPN tunnel availability,
as well as some throughput, but also makes this pretty simple to deploy.

To implement this, just deploy this design but leave out anything related to multiple VPN gateway pods, and the router pods. Then just adjust the client network attachment
definition to set the VPN gateway IP address as the default gateway.

### Example simple setup
I have not tested the below, but it should be enough to implement the simple version of this setup. If you try this and encounter an issue, please report it to me so that I can fix it.

Prerequisites:
* Multus CNI plugin
* Whereabouts IPAM plugin
* bridge CNI plugin
* node-network-operator (if not deploying overlay network via distro-specific config)

VXLAN overlay network (optional, deploy something similar via distro-specific config alternatively)
```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/solidDoWant/node-network-operator/refs/tags/v0.0.6/schemas/link_v1alpha1.json
# This is the link that pods will join to via the bridge CNI plugin. The bridge VNI plugins will add one end of a veth pair to this bridge, and
# the other end to the pod's network namespace.
# This bridge will also have a VXLAN interface added to it, so that pods can communicate across nodes.
apiVersion: nodenetworkoperator.soliddowant.dev/v1alpha1
kind: Link
metadata:
  name: vpn-gateway-bridge
spec:
  # This must be 15 characters or less.
  interfaceName: vpn-gw-bridge0
  bridge:
    # This matches the wireguard MTU, which is the limiting factor for the VPN gateway network.
    mtu: 1420
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/solidDoWant/node-network-operator/refs/tags/v0.0.6/schemas/link_v1alpha1.json
# This is the link that the VXLAN should use for transceiving packets. 
# YOU MUST CHANGE THIS to match the primary interface on your nodes.
apiVersion: nodenetworkoperator.soliddowant.dev/v1alpha1
kind: Link
metadata:
  name: vpn-gateway-vxlan-dev
spec:
  interfaceName: bond0
  # Important: This link type means that other links can _reference_ it, but the operator itself will not change anything about the link.
  # The operator will just assume that the link exists and is properly configured.
  unmanaged: {}
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/solidDoWant/node-network-operator/refs/tags/v0.0.6/schemas/link_v1alpha1.json
# The VXLAN links deployed by this connect the bridges on each node to each other, allowing pods to communicate across nodes.
apiVersion: nodenetworkoperator.soliddowant.dev/v1alpha1
kind: Link
metadata:
  name: vpn-gateway-vxlan
spec:
  interfaceName: vpn-gw-vxlan0
  vxlan:
    # This is an arbitrary value but it needs to be unique across all VXLANs in the cluster.
    vnid: 1000
    # This address is subnet-local, and will not be propagated to other subnets by routers.
    remoteIPAddress: 224.0.0.88
    # This is the device that will carry the VXLAN traffic.
    device:
      name: vpn-gateway-vxlan-dev
    # Tie the interface to the bridge so that pods veth interfaces can send traffic over the VXLAN.
    master:
      name: vpn-gateway-bridge
    # This matches the wireguard MTU, which is the limiting factor for the VPN gateway network.
    # It is also more than 50 bytes smaller than the underlying bond0 MTU of 9000.
    mtu: 1420
```

Network attachment definitions:
```yaml
---
# This will be assigned to the gateway pod
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: gateway-network-vpn-gateway-pod
spec:
  config: |
    {
      "cniVersion": "0.3.0",
      "name": "gateway-network-vpn-gateway-pod",
      "type": "bridge",
      "bridge": "vpn-gw-bridge0",
      "ipam": {
        "type": "whereabouts",
        "range": "192.168.24.0/24",
        "range_start": "192.168.24.254",
        "range_end": "192.168.25.254"
      },
      "mtu": 1420
    }
---
# This will be assigned to client pods
# See above section about excluding specific subnets if 10.0.0.0/8 is not sufficient
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: gateway-network-client-pods
spec:
  config: |
    {
      "cniVersion": "0.3.0",
      "name": "gateway-network-client-pods",
      "type": "bridge",
      "bridge": "vpn-gw-bridge0",
      "ipam": {
        "type": "whereabouts",
        "range": "192.168.24.0/24",
        "range_start": "192.168.24.1",
        "range_end": "192.168.25.127",
        "routes": [
          {"dst": "0.0.0.0/5"},
          {"dst": "8.0.0.0/7"},
          {"dst": "11.0.0.0/8"},
          {"dst": "12.0.0.0/6"},
          {"dst": "16.0.0.0/4"},
          {"dst": "32.0.0.0/3"},
          {"dst": "64.0.0.0/2"},
          {"dst": "128.0.0.0/1"}
        ],
        "gateway": "192.168.26.254"
      },
      "mtu": 1420
    }
```

VPN gateway (deployed via Flux HelmRelease with bjw-s' app-template chart, but can also be deployed as a "raw" pod, deployment, etc.):
```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: vpn-gateway
spec:
  interval: 5m
  chart:
    spec:
      chart: app-template
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        namespace: flux-system
        name: bjw-s-charts
      version: 4.2.0
  values:
    controllers:
      vpn-gateway:
        pod:
          annotations:
            # Attach the pod to the VPN gateway network using the gateway-network-vpn-gateway-pod network attachment definition.
            # The interface name within the pod will be vpn-gw-veth0.
            k8s.v1.cni.cncf.io/networks: gateway-network-vpn-gateway-pod@vpn-gw-veth0
          dnsConfig:
            options:
              - name: ndots
                value: "1"
        initContainers:
          # Masquerade incoming traffic from the client pods (e.g. 192.168.24.100) so that it looks like it's coming from the gluetun pod itself (i.e. "${WIREGUARD_ADDRESSES}")
          # This is needed so that the VPN exit node understands where to send traffic back to. It won't know how to reach client pods, just the gateway pod.
          setup-ingress-snat:
            # Use the gluetun image just to avoid pulling another image. All this needs is the iptables CLI.
            image:
              repository: qmcgaw/gluetun
              tag: v3.40.0
            env:
              VPN_INTERFACE: tun0 # Interface for VPN traffic
            command:
              - ash
              - -c
              - iptables -t nat -A POSTROUTING -o "${VPN_INTERFACE}" --match addrtype ! --dst-type LOCAL,BROADCAST,ANYCAST,MULTICAST -j MASQUERADE
            securityContext:
              capabilities:
                add:
                  - NET_ADMIN
        containers:
          gluetun:
            image:
              repository: qmcgaw/gluetun
              tag: v3.40.0
            env:
              VPN_TYPE: wireguard
              WIREGUARD_MTU: "1420"
              # SET THESE HERE OR VIA A SECRET
              VPN_SERVICE_PROVIDER: your-provider
              WIREGUARD_ADDRESSES: 1.2.3.4
              SERVER_COUNTRIES: your-country
              WIREGUARD_PUBLIC_KEY: your-public-key
              WIREGUARD_PRIVATE_KEY: your-private-key
              WIREGUARD_PRESHARED_KEY: your-preshared-key
            lifecycle:
              # From https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/kubernetes.md#adding-ipv6-rule--file-exists
              # This must run on every container start, not the pod start, as it handles a gluetun bug when the container
              # is restarted.
              postStart:
                exec:
                  command:
                    - /bin/sh
                    - -c
                    - ip rule del table 51820 || true
            securityContext:
              capabilities:
                add:
                  - DAC_OVERRIDE
                  - MKNOD
                  - NET_ADMIN
                  - CHOWN
            probes:
              # From https://github.com/qdm12/gluetun-wiki/blob/main/faq/healthcheck.md#docker-healthcheck
              readiness: &gluetun_probe
                enabled: true
                custom: true
                spec: &gluetun_probe_spec
                  initialDelaySeconds: 15
                  exec:
                    command:
                      - /gluetun-entrypoint
                      - healthcheck
              liveness:
                <<: *gluetun_probe
                spec:
                  <<: *gluetun_probe_spec
                  initialDelaySeconds: 0
```

Example client pod:
```yaml
---
apiVersion: v1
kind: Pod
metadata:
  name: get-public-ip
  annotations:
    # Replace the "networking" prefix with whatever namespace the network attachment definition is in.
    k8s.v1.cni.cncf.io/networks: networking/gateway-network-client-pods@vpn-gw-veth0
spec:
  containers:
  - name: get-public-ip
    image: nicolaka/netshoot
    command:
      - sh
      - -c
      - |
        ip addr show vpn-gw-veth0
        while true; do
          curl -s https://ifconfig.me
          echo
          sleep 60
        done
```

### Ingress routing and VPN provider port forwarding

There's a couple of different approaches to forwarding ingress traffic to services. The first option is to just create a service with a static IP address, and forward the traffic
there. The traffic will leave via the primary CNI, and kube-proxy will handle getting it to where it needs to go. 

This doesn't work if you're using a kube-proxy replacement that does not use the kernel network stack. Cilium, for example, has basically replaced the entire kernel network stack
with eBPF programs. This approach has some  nice benefits, but it also requires that traffic enter and exit the custom network stack at specific points. If traffic is
forwarded to a service IP address _without_ changing the source IP address to the pod-assigned address, it will simply enter the Cilium stack and disappear.

SNATing the traffic works here, but it comes at a major cost - the destination service will only see the SNATed IP address, and not the true source address. This makes it look like
all connections are coming from the same place (VPN gateway pods). On the other hand, it does bring all the features of traffic managed by the primary CNI, such as packet filtering
(netpols), and automatic routing to available endpoints.

The alternative is forwarding traffic to a fixed set of IP addresses on the VPN network. This keeps all the traffic in normal kernel network stack, so there is no need to SNAT it.
Traffic source IP addresses are preserved, but you can't _easily_ filter the traffic. In addition, because traffic must be sent to one specific address, and availability and load
balancing must be implemented manually instead of relying on kube-proxy. This can be accomplished with keepalived for VRRP and IPVS management, as I'm doing in my setup.

Here's an untested example of setting up port-forwarding via the VPN gateway network:

Gateway pod changes:
```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: vpn-gateway
spec:
  interval: 5m
  chart:
    spec:
      chart: app-template
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        namespace: flux-system
        name: bjw-s-charts
      version: 4.2.0
  values:
    controllers:
      vpn-gateway:
        initContainers:
          # APPEND THIS CONTAINER to the above vpn-gateway setup
          setup-ingress-dnat:
            # Use the gluetun image just to avoid pulling another image. All this needs is the iptables CLI.
            image:
              repository: qmcgaw/gluetun
              tag: v3.40.0
            env:
              VPN_INTERFACE: tun0 # Interface for VPN traffic
              GATEWAY_NETWORK_INTERFACE: vpn-gw-veth0 # Interface for the VPN subnet
              # Format: <VPN port>:<VPN gateway network destination IP>:<VPN gateway network destination port>
              # All traffic for the ports that are forwarded by the VPN exit node will be forwarded/DNATed again to these addresses.
              PORT_MAPPINGS: >
                1111:192.168.24.128:6666
                2222:192.168.24.129:7777
                3333:192.168.24.130:8888
                4444:192.168.24.131:9999
                5555:192.168.24.132:01234
              WIREGUARD_ADDRESSES: 1.2.3.4
            command:
              - ash
              - -c
              - |
                set -x

                PROTOCOLS=${PROTOCOLS:-"tcp udp"}

                # Rewrite packets that are port-forwarded by the VPN to the destination IP:Port combo
                for PORT_MAPPING in ${PORT_MAPPINGS}; do
                    VPN_PORT="${PORT_MAPPING%%:*}"
                    PORT_FORWARD_DESTINATION="${PORT_MAPPING#*:}"
                    for PROTOCOL in ${PROTOCOLS}; do
                        iptables -t nat -A PREROUTING -i "${VPN_INTERFACE}" -p "${PROTOCOL}" --dst "${WIREGUARD_ADDRESSES}" --dport "${VPN_PORT}" -j DNAT --to-destination "${PORT_FORWARD_DESTINATION}"
                    done
                done
            securityContext:
              capabilities:
                add:
                  - NET_ADMIN
```

Network attachment definitions for pods that want to accept traffic:
```yaml
---
# These are all identical to the `gateway-network-client-pods` NAD except they only have a single IP address listed.
# Instead of using whereabouts IPAM plugin here, the static plugin could be used. I'm just specifying whereabouts to reduce the number of dependencies.
# Most (if not all) of this could also be specified directly on client pods, but I generally prefer to keep all this config in one place.
# One is needed per port. Add/remove NADs as needed.
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: gateway-network-ingress-client-port-1
spec:
  config: |
    {
      "cniVersion": "0.3.0",
      "name": "gateway-network-ingress-client-port-1",
      "type": "bridge",
      "bridge": "vpn-gw-bridge0",
      "ipam": {
        "type": "whereabouts",
        "range": "192.168.24.0/24",
        "range_start": "192.168.24.128",
        "range_end": "192.168.24.128",
        "routes": [
          {"dst": "0.0.0.0/5"},
          {"dst": "8.0.0.0/7"},
          {"dst": "11.0.0.0/8"},
          {"dst": "12.0.0.0/6"},
          {"dst": "16.0.0.0/4"},
          {"dst": "32.0.0.0/3"},
          {"dst": "64.0.0.0/2"},
          {"dst": "128.0.0.0/1"}
        ],
        "gateway": "192.168.26.254"
      },
      "mtu": 1420
    }
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: gateway-network-ingress-client-port-2
spec:
  config: |
    {
      "cniVersion": "0.3.0",
      "name": "gateway-network-ingress-client-port-2",
      "type": "bridge",
      "bridge": "vpn-gw-bridge0",
      "ipam": {
        "type": "whereabouts",
        "range": "192.168.24.0/24",
        "range_start": "192.168.24.129",
        "range_end": "192.168.24.129",
        "routes": [
          {"dst": "0.0.0.0/5"},
          {"dst": "8.0.0.0/7"},
          {"dst": "11.0.0.0/8"},
          {"dst": "12.0.0.0/6"},
          {"dst": "16.0.0.0/4"},
          {"dst": "32.0.0.0/3"},
          {"dst": "64.0.0.0/2"},
          {"dst": "128.0.0.0/1"}
        ],
        "gateway": "192.168.26.254"
      },
      "mtu": 1420
    }
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: gateway-network-ingress-client-port-2
spec:
  config: |
    {
      "cniVersion": "0.3.0",
      "name": "gateway-network-ingress-client-port-3",
      "type": "bridge",
      "bridge": "vpn-gw-bridge0",
      "ipam": {
        "type": "whereabouts",
        "range": "192.168.24.0/24",
        "range_start": "192.168.24.130",
        "range_end": "192.168.24.130",
        "routes": [
          {"dst": "0.0.0.0/5"},
          {"dst": "8.0.0.0/7"},
          {"dst": "11.0.0.0/8"},
          {"dst": "12.0.0.0/6"},
          {"dst": "16.0.0.0/4"},
          {"dst": "32.0.0.0/3"},
          {"dst": "64.0.0.0/2"},
          {"dst": "128.0.0.0/1"}
        ],
        "gateway": "192.168.26.254"
      },
      "mtu": 1420
    }
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: gateway-network-ingress-client-port-2
spec:
  config: |
    {
      "cniVersion": "0.3.0",
      "name": "gateway-network-ingress-client-port-4",
      "type": "bridge",
      "bridge": "vpn-gw-bridge0",
      "ipam": {
        "type": "whereabouts",
        "range": "192.168.24.0/24",
        "range_start": "192.168.24.131",
        "range_end": "192.168.24.131",
        "routes": [
          {"dst": "0.0.0.0/5"},
          {"dst": "8.0.0.0/7"},
          {"dst": "11.0.0.0/8"},
          {"dst": "12.0.0.0/6"},
          {"dst": "16.0.0.0/4"},
          {"dst": "32.0.0.0/3"},
          {"dst": "64.0.0.0/2"},
          {"dst": "128.0.0.0/1"}
        ],
        "gateway": "192.168.26.254"
      },
      "mtu": 1420
    }
---
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: gateway-network-ingress-client-port-2
spec:
  config: |
    {
      "cniVersion": "0.3.0",
      "name": "gateway-network-ingress-client-port-5",
      "type": "bridge",
      "bridge": "vpn-gw-bridge0",
      "ipam": {
        "type": "whereabouts",
        "range": "192.168.24.0/24",
        "range_start": "192.168.24.132",
        "range_end": "192.168.24.132",
        "routes": [
          {"dst": "0.0.0.0/5"},
          {"dst": "8.0.0.0/7"},
          {"dst": "11.0.0.0/8"},
          {"dst": "12.0.0.0/6"},
          {"dst": "16.0.0.0/4"},
          {"dst": "32.0.0.0/3"},
          {"dst": "64.0.0.0/2"},
          {"dst": "128.0.0.0/1"}
        ],
        "gateway": "192.168.26.254"
      },
      "mtu": 1420
    }
```

Client pod example:
```yaml
---
apiVersion: apps/v1
kind: Pod
metadata:
  name: vpn-ingress-traffic
  annotations:
    # Replace the "networking" prefix with whatever namespace the network attachment definitions are in.
    k8s.v1.cni.cncf.io/networks: networking/gateway-network-ingress-client-port-1@vpn-gw-veth0
spec:
  containers:
    - name: vpn-ingress-traffic
      image: mendhak/http-https-echo:37
      env:
        - name: HTTP_PORT
          value: "5555"
      securityContext:
        capabilities:
          drop:
            - ALL
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
```