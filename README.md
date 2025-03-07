# infra-mk3

This repo is both the documentation of, and, in part, the implementation of the fourth major iteration of my homelab infrastructure. The primary objective of this implementation is to provide a reliable and stable way for me to continue to develop my technical skills. A brief history and more information on my motivation is written up [here](./docs/motivation%20and%20background.md).

Excluding secrets, this project is designed to be reproducible by anybody with the same physical hardware. See [here](./docs/setup.md) to get started.

## Overview
- [infra-mk3](#infra-mk3)
  - [Overview](#overview)
  - [Hardware Architecture](#hardware-architecture)
    - [Power](#power)
    - [Network](#network)
      - [Physical layout](#physical-layout)
      - [Virtual/VLAN layout](#virtualvlan-layout)
      - [Kubernetes route propagation](#kubernetes-route-propagation)
      - [Firewall rules and NAT port forwarding](#firewall-rules-and-nat-port-forwarding)
      - [External DNS](#external-dns)
    - [Storage](#storage)
      - [Persistent storage](#persistent-storage)
      - [Backups](#backups)
    - [Compute](#compute)
      - [VM host](#vm-host)
      - [Kubernetes hosts](#kubernetes-hosts)
  - [Software architecture](#software-architecture)
    - [Workload deployments](#workload-deployments)
    - [Monitoring](#monitoring)
    - [Updates](#updates)
    - [Identity and access management](#identity-and-access-management)
    - [Secrets](#secrets)
    - [Bootstrapping](#bootstrapping)

<!-- 
TODO:
* Projects used
* Local setup/dev tooling
* Community links
* Uncommon approaches/new solutions discovered
-->

## Hardware Architecture

The system architecture is broken up into several high-level components. All endpoint devices are out of scope unless explicitly specified. Unless otherwise stated, all hardware lives inside [a 45U fully enclosed server rack](https://assets.belden.com/m/27ebe83e4015e128/original/Rack-Cabinet-Systems-Belden-2019-02.pdf).

A full, detailed document describing the hardware used is available [here](./docs/hardware.yaml) in a machine-parsable format.


### Power

Power delivery in a single point of failure in my lab. I "only" have one power company, breaker panel, circuit, [UPS](https://www.vertiv.com/en-us/products-catalog/critical-power/uninterruptible-power-supplies-ups/ps1500rt3-120w/), and [PDU](https://www.vertiv.com/en-us/products-catalog/critical-power/power-distribution/vertiv-mph2-mphr3141/), all wired in series. The UPS helps protect against short power outages, but if it, the PDU, or device power supplies fail, then at least one device will fail.

Removing any of the single points of failure upstream of the UPS would be prohibitively expensive. I could add another UPS and an automatic transfer switch (ATS) to handle battery and power converter failures, but it's probably not worth the cost. Based on current prices, I could probably get another 1500VA UPS with new batteries, along with an ATS for about $600 to my door. Typically I only have about one power outage per year that lasts for more than 2-3 minutes, and even with older batteries, my UPS can handle this without issue.

I could also add another PDU in parallel with my current PDU, but again, I wouldn't see much benefit for the cost here. Most of the hardware I'm using only has one power supply, so I would either need to add an ATS for each device of these devices. I would also raise my power costs for devices that have multiple power supplies, as each additional supply has a power "overhead" cost when plugged in, even in active/passive configuration.

```mermaid
flowchart LR
  power[Power grid]
  breaker[Breaker panel]
  circuit[120V, 20A circuit]
  UPS[Liebert PS1500RT3-120W UPS]
  PDU[Vertiv MPH2 MPHR3141 PDU]
  power --> breaker --> circuit --> UPS --> PDU
```

### Network

The source of truth for this information, which also contains additional details, is available [here](./docs/network.yaml) in a machine-parsable format.

#### Physical layout
My network uses a pretty standard router-on-a-stick, with some redundancies for high availability. At a high level, I have my ISP's XGS-PON connected via a XGS-PON SFP+ transceiver to a virtual switch (bridge) where [it is multiplexed](./ansible/remote/routers/opnsense/files/10-wancarp) between two OPNSense router VMs. These routers share another bridge that connects to a 56/40 Gbps Mellanox switch via a QSFP+ DAC. The 40 Gbps switch connects to an ICX 7150 via a QSFP+ to 4x SFP+ breakout DAC, with all four interfaces configured in a Link Aggregation Group (LAG) in 802.3ad LACP mode. All other devices are connected to the Mellanox switch for 10, 40, and 56 Gbps links, or the Brocade access switch for 1 Gbps PoE links.

```mermaid
flowchart LR
  ISP --> router[OPNSense HA routers] --> sw1[40Gbps top of rack switch] --> sw2[1Gbps access switch]
  sw1 --> Servers
  sw2 --> end_devices[End devices]
  sw2 --> misc_devices[Miscellaneous devices]
```

Despite roughly following a tree topology, there are several uncommon design elements:
* Instead of using my ISP-provided BGW320-505 gateway, I am using a [WAS-110 XGS-PON ONT "stick"](https://flyteccomputers.com/halny-networks-hlx-sfpx) to connect to my ISP's network. I do this instead of setting up the ISP-provided gateway in "passthrough mode" for several reasons:

  * It removes a point of failure.
  * It consumes *significantly* less power - 1.5 W max vs ~20 W.
  * It avoids a hardware limitation with the gateway where it can, at most, track 8192 connections at once (and has performance issues well before that limit). The replacement can support up to 16384.

* I'm running two OPNSense instances as routers. These are configured in a failover group, and use the [Common Access Redundancy Protocol (CARP)](https://docs.opnsense.org/manual/hacarp.html) on internal VLANs high availability. This allows me to change one instance at a time (either a reconfiguration or a software update) without causing an outage. This is a little bit difficult to handle on the WAN interface. My ISP only supplies me with a single dynamic IPv4 address, with a long DHCP lease. This means that the WAN interface of each router in the failover group needs to be the same... but this doesn't work because the WAN switch will not know which port to send packets to. To work around this, I am running a script, triggered on CARP failover event, that disables the WAN interface on the new CARP backup instance, and enables it on the new CARP active instance. This inevitably leads to some packet loss, but works reasonably well.

  There are a few ways that I might try to improve this in the future:
  * I could enable the WAN port of both instances, then use static ARP table entries in the WAN and LAN network bridges. I could then run a service somewhere else that would monitor the router status. Upon failure, the service would change the static ARP table entries in the network WAN/LAN network bridges on the underlying OPNSense node. As long as connection state, DHCP server state, etc. replication is configured properly, this should be a near-seamless transition with little packet loss. This would also require setting a static IP in OPNsense, so the script would need to handle this as well.
  * Right now everything is running on a single Proxmox node. When I want to change something on this node (such as a reboot after a software update), then I will have an internet outage while the host and OPNSense instances reboot. I could mitigate this by adding another Proxmox node, alongside a physical switch for the WAN, and configuring live VM migrations between the Proxmox nodes. This would allow me to update the underlying nodes without an outage, at an increased power cost (which I'm trying to optimize for).

* I have a 56 Gbps Ethernet link between the Proxmox R730XD server and the Mellanox switch. This requires all Mellanox network hardware (NIC, cable, switch). If I remember correctly, it's achieved via a line coding scheme in the physical coding sublayer with less overhead (128b/130b maybe?), alongside hardware with a higher SNR to reduce the bit error rate.

* The Brocade access switch unfortunately does not have any QSFP+ cages, but it does have 8x SFP+ cages. I'm using a squid/breakout DAC cable to establish four separate 10 Gbps links between the switches, combined in a LAG. I also have LAGs with each of the three MS-01 nodes, formed with a pair of 10 Gbps links. The MS-01 LAG uses two separate DAC cables on each node (connected, in total, to two upstream QSFP+ ports). By using LACP, this allows prevents downtime in the event that a cable fails (or, more likely, is removed accidentally).

* Not diagrammed is a fiber patch panel with LC connectors. Inside/behind the panel, there are splitter cables that split fiber pairs MPO-8 type B cables to 4x LC connectors. I then run LC UPC OM3 from this patch panel to various devices throughout my home.

Here's the network in more detail:
```mermaid
flowchart LR
  isp["ISP OLT/ODN (XGS-PON)"]
  subgraph "R730 (virtualized routers)"
    direction LR

    ont[WAS-110 SFP+ XGS-PON ONT]
    sfp[Intel X520 SFP+ NIC]
    wan_bridge[WAN network bridge on Proxmox]
    opnsense1[OPNSense VM CARP primary]
    opnsense2[OPNSense VM CARP backup]
    lan_bridge[LAN bridges on Proxmox]
    qsfp[Mellanox MCX314A-BCCT QSFP+ NIC]
    idrac[iDRAC 1000Base-T]

    sfp --> wan_bridge
    wan_bridge <--> opnsense2 <--> lan_bridge
    wan_bridge <--> opnsense1 <--> lan_bridge
    lan_bridge <--> qsfp
  end
  subgraph Switches
    direction TB

    sx6036[Mellanox SX6036 36 port QSFP+ InfiniBand/Ethernet switch]
    icx7250[Brocade ICX 7250 24P 4x10 SFP+]

    sx6036 <--QSFP+ breakout DAC cable to 4x SFP+ LAG @ 10Gbps/link--> icx7250
  end
  subgraph 3x MS-01s
    direction LR

    ms01_vpro[vPro-enabled 1000Base-T NIC]
    ms01_sfp[2x SFP+ NIC]
  end
  subgraph misc_dev["Miscellaneous devices (all 1000Base-T)"]
    direction LR

    pdu[Vertiv MPH2 MPHR3141 PDU]
    ups[Liebert PS1500RT3-120W UPS]
    tape[IBM TS3200 tape library]
    aps[Unifi U6+ APs]
  end

  isp <--SC/APC OS2 fiber--> ont <--> sfp
  qsfp <--QSFP+ DAC cable @ 56Gbps--> sx6036
  sx6036 <--2x QSFP+ breakout DAC cable to 4x SFP+ LAG @ 10Gbps/link--> ms01_sfp
  idrac <--> icx7250
  icx7250 <--> ms01_vpro
  icx7250 <--> misc_dev
```

As shown above, there are still several single points of failure with this design. Most of these I could easily mitigate by adding additional hardware (switches, Proxmox host) and changing the topology a bit. Devices would connect to two switches instead of one, and form a multi-chassis LAG (MLAG) with the links. If I deployed another Proxmox host, then I could live-migrate router VMs for zero-downtime hypervisor updates, and I could tolerate a single host hardware failure. Lastly, I could add another ISP for a multi-WAN setup, buy a block of IP addresses, and setup multicast BGP peering with the ISPs.

#### Virtual/VLAN layout

My physical network is subdivided into several virtual LANs (VLANs) spreading across the physical and virtual routers and switches.

| ID  | Name          | Description                                                                                                       | IP address ranges                                    |
| --- | ------------- | ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| 100 | Management    | Out of band management (iDRAC, vPro) and hypervisor access (Proxmox web interface)                                | 10.1.0.0/16                                          |
| 200 | Hosts         | Primary network access for machines that run workloads, used for SSH, WAN access, k8s control plane traffic, etc. | 10.2.0.0/16                                          |
| 300 | Kubernetes    | CNI traffic between k8s pods                                                                                      | 10.3.0.0/16 (BGP), 10.32.0.0/28 (Kubernetes subnets) |
| 400 | User devices  | End user devices (desktops, laptops, etc.)                                                                        | 10.4.0.0/16                                          |
| 500 | Guest devices | End user guest devices, less trusted with only Internet access and network segregation (PVLAN)                    | 10.5.0.0/16                                          |
| 600 | IoT devices   | Untrusted IoT devices with limited point to point internal access (PVLAN)                                         | 10.6.0.0/16                                          |

Most VLANs have a dedicated address range within the VLAN subnet that is allocated for DHCP leases.

VLANs are further subdivided (on paper, within the same subnet) for specific purposes. The first /24 is exclusively for network devices, with the gateway IP being the last non-broadcast IP address in the CIDR.

#### Kubernetes route propagation

Kubernetes pods may be scheduled on multiple nodes, and load balancer virtual IP addresses need to be reachable from several nodes. All nodes running Cilium (Kubernetes CNI) have BGP peering setup with the routers. Pod and load balancer IP addresses are announced from all nodes in the cluster.

Unfortunately, [Cilium doesn't support BFD yet](https://github.com/cilium/cilium/issues/22394). When/if BFD support is added, I will deploy it. For now, I just have to accept packet loss when a node goes offline.

#### Firewall rules and NAT port forwarding

OPNSense firewall rules and NAT port forwarding are handled via a custom OPNSense controller running inside the cluster. Custom resources and load balancers with specific annotations can allow external traffic flow through the router and firewall to Kubernetes services.

#### External DNS

I have a publicly-resolvable domain resolving to my WAN IP address. Because my IP address is dynamic (although it changes infrequently), I have custom tooling update this A record periodically. The external DNS project is used to manage records that should resolve to specific services within my cluster.

DNS records are pushed to Cloudflare for public resolution. Internally, Unbound (the DNS resolver on the OPNsense routers) forwards requests for the domain to the cluster's CoreDNS service.

### Storage

Storage is broken down into two categories: ephemeral and persistent. Ephemeral storage can be lost/corrupted/destroyed without consequence, as long as it isn't a single point of failure. All Kubernetes nodes use a cheap consumer NVMe SSD as their OS disk, and for persistent storage. If a drive starts to fail, I can simply take the node offline and replace the failing part. The server running the router VMs needs to be a little more fault tolerant as it's a single point of failure. This server uses a pair of WD BLACK SN850X consumer SSDs in a ZFS mirror pool. These SSDs are a little nicer than what I'm using in my Kubernetes nodes, and (anecdotally) I've had them work flawlessly for years in a similar environment.

#### Persistent storage

Persistent storage is much more important. Not only should it tolerate several drive failures before data loss, but it needs to be backed up as well. I have two forms of persistent storage for day-to-day operations: a NetApp DS4246 disk shelf for bulk storage, and a Ceph cluster for fast storage.

The disk shelf is attached to the Proxmox host via a LSI 9207-8e host bus adapter (HBA). The disk shelf's IO modules (IOM) are both connected to the HBA. Proxmox configures the eight SAS 12 8TB drives in a ZFS RAID-Z2 pool. ZFS can access the drive with an active-active multipath connection, which both allows for a faster link speed, and can handle one cable or IOM failure. With this design, only the ZFS host itself and the HBA are single points of failure. I may add a second HBA in the future to remove a single point of failure.

The ZFS pool also employs a mirrored pair of 58GB Intel 800P Optane drives for SLOG. This drastically improves performance with sync writes, which NFS makes heavy use of. The datasets in the pool are exposed to the network either by NFS (for most of the storage), or via iSCSI, managed by [democratic-csi](https://github.com/democratic-csi/democratic-csi) for Kubernetes. This is primarily used for media storage, and Kubernetes workloads that require a lot of unshared, slow storage (such as log scrapers).

Ceph, managed by Rook within the Kubernetes cluster, is used for fast, durable storage for cluster workloads. The cluster can tolerate up to two drive failures before losing data. Each node in the cluster includes a Samsung 1.92TB PM9A3 enterprise U.2 SSD. While these are fairly fast SSDs, the critically important part is that they include "power loss protection" (PLP). Despite the name, this feature gives little benefit when there is a power outage. Instead, it allows the drives to report "success" on sync writes significantly faster than consumer drives. This is because data from sync writes can be stored in fast(er), volatile RAM, and still be guaranteed to be written to the disk (synced) in all cases. Most if not all Ceph writes are `sync` writes, so this is key to ensuring that the drives perform well. Without PLP, even high end SSDs perform like hard drives when used in a Ceph cluster.

#### Backups

Important data and applications are backed up to via [a backup tool that I developed](https://github.com/solidDoWant/backup-tool). Backups are stored in a (relatively) large ZFS pool on one of my hosts. After a backup occurs, a snapshot of the ZFS dataset is taken. This solution allows for:

* Consistent backups of application workloads
* Selective backups of specific paths within volumes
* Direct file access to the backups (many other solutions require an object store)
* Compression of backup data
* Incremental backups with support for deletion of old backups

Periodically, backups of ZFS datasets are written to LTO tape via an IBM TS3200 tape library. Backup files are written, via custom tooling, to tapes "formatted" with Linear Tape File System (LTFS). Backups are typically incremental, with an infrequent full backup. When full backups are taken, an additional tape copy is made and taken offsite.

This procedure satisfies the [3-2-1 backup rule](https://www.backblaze.com/blog/the-3-2-1-backup-strategy/).

### Compute

I currently have four physical hosts. One R730XD running Proxmox, and three MS-01 running Talos. Hostnames follow the format `$OS-$PURPOSE-$NUMBER`. For the current hosts, these are:
* `proxmox-vm-host-01`
* `talos-k8s-mixed-0{1..4}` (mixed referring to the node running both the control plane, and workloads)

All hosts have two network interface groups of one or more interfaces. The first one is an out of band management port (iDRAC, vPro), and the second is a trunk port for OS and application network traffic.

#### VM host

The VM host runs Proxmox as a hypervisor and uses a pair of Intel Xeon E5-2667 v4 8 core/16 thread processors running at 3.2 GHz. It has 256 GB of ECC DDR4 clocked 2400 MT/s split between the hypervisor and VMs. It includes a number of PCIe cards:
* A LSI 9207-8e SAS HBA connected to the NetApp disk shelf
* Two QLogic QLE2562 fiber channel HBA connected to the drives in the IBM TS3200 tape library
* A Mellanox ConnectX 3 Pro MCX314A-BCCT dual QSFP+ NIC connected to the Mellanox switch
* A Dell NVMe Enablement kit P31H2 connected to the last for drive slots of the R730XD backplane, which contains two OS and two ZFS SLOG NVMe drives via NVMe to U.2 adapters

#### Kubernetes hosts

All three current dedicated Kubernetes hosts are identical. They are all [Minisforum MS-01](https://store.minisforum.com/products/minisforum-ms-01) small form factor PCs. Each one is equipped with an Intel i9-13900H 14 core/20 thread processor a clock rate of up to 5.4 GHz. The RAM is comprised of two 48 GB DDR5 modules at running at 5200 MT/s. All three nodes use generic M.2 NVMe drives for boot (without a mirror), and contain a Samsung 1.92TB PM9A3 enterprise U.2 SSD exclusively for Ceph. The nodes are connected with three interfaces to the network: one 1000Base-T port for vPro access, and two SFP+ cages forming a LAG.

## Software architecture

Most of my workloads run on Kubernetes. A small handful of workloads that cannot be containerized are ran as VMs. This includes OPNSense router instances, and Kubernetes nodes with specific hardware and kernel requirements. Proxmox is used as a hypervisor for these VMs.

Kubernetes nodes run Talos, an immutable operating system. They use containerd as a container runtime by default, and Kata Containers where more isolation is needed. Cilium CNI handles all cluster networking, configured with native routing and BGP peering with OPNSense. Rook Ceph CSI is used for fast, small, highly available storage, and democratic-csi is used with the `zfs-generic-iscsi` driver slow, large, fallible storage. A NFS share, backed by a ZFS dataset, is used for large files that may need to be accessed outside of the cluster, such as media files.

### Workload deployments

After cluster bootstrapping is complete, Flux CD handles the software lifecycle for all cluster workloads. Except for one-off testing changes, all workload changes are committed to this repo. Upon commit to master, GitHub notifies Flux via a webhook of the change, and Flux deploys it. Where possible, bootstrap resources are "adopted" by Flux after initial deployment, so that it can automatically handle updates and changes to them. This structure allows for an easily redeployable cluster, as well as a complete history of all changes, and rollback support.

### Monitoring

Monitoring is handled via Victoria Metrics with Grafana for visualization. Alerts (enabled conservatively) are sent to a private Discord channel. Metrics and logs are stored on bulk ZFS-backed storage with compression enabled, with a ZFS SLOG to help with the frequent sync writes.

### Updates

All dependencies within the repo are handled via Renovate. Renovate runs in "self-hosted" mode as a cron job within the cluster. Unfortunately, I only have one cluster available so I am not able to implement a QA/staging/production split for update PRs, so update PRs are deployed on a "push and pray" basis. Many updates are automatically merged, although this maintenance reduction comes at a greatly increased risk of a supply chain attack.

Host OS updates are handled via system-upgrade-controller, which ensures that nodes match the OS version specified in the repo (which is managed by Renovate). Additional tooling is needed to handle auto updates of Proxmox and OPNSense nodes (along with rollback on failure).

### Identity and access management

User identities are managed with Authentik. In most cases, Authentik also handles authorization and authentication for web applications as well. Teleport Enterprise is used for access to "infra" level access (such as SSH) for both admin access, and machine to machine access (such as democratic-csi to zfs host SSH).

Unfortunately Authentik does not currently have a k8s operator, so configuration is handled via configmaps that k8s-sidecar dynamically loads into the Authentik pod.

### Secrets

All secret values are stored in the repo via SOPS and encrypted with AGE. Flux can then access and decrypt these secrets, and pass them where needed.

### Bootstrapping

Bootstrapping is handled via Taskfile scripting where possible, otherwise, it is done manually and documented thoroughly. After bootstrapping is complete, Taskfiles are only used to make periodic, one-off tasks (typically for development) more convenient, and is not used for day to day operations.
