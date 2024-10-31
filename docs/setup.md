# Setup

This document details the procedure for setting up the lab from scratch. Outside of secret values, this should be sufficient to identically produce the same infrastructure and applications that I'm running.

- [Setup](#setup)
- [Physical deployment](#physical-deployment)
- [Hardware configuration](#hardware-configuration)
- [Cluster bootstrapping](#cluster-bootstrapping)


# Physical deployment

The following hardware is assembled as documented [here](./hardware.yaml) and racked as documented below:

![Rack diagram](./assets/images/rack_architecture.drawio.svg)

# Hardware configuration

Run through the following guides, in order:
* [Mellanox SX6036 setup](./setup-sx6036.md)
* [Brocade ICX 7250 setup](./setup-icx7250.md)
* [MPR3141 setup](./setup-mpr3141.md)
* [R730XD setup](./setup-r730xd.md)
* [MS-01 setup](./setup-ms-01.md)

# Cluster bootstrapping

After all hardware has been deployed and configured, run `task:deploy-flux` to bootstrap Flux, which deploys all workloads to the cluster.

<!-- 
TODO:
* Tape library
* UPS
* KVM
 -->
