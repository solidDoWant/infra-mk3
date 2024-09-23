# Setup

This document details the procedure for setting up the lab from scratch. Outside of secret values, this should be sufficient to identically produce the same infrastructure and applications that I'm running.

- [Setup](#setup)
- [Physical setup](#physical-setup)
- [Network](#network)


# Physical setup

The following hardware is assembled as documented [here](./hardware.yaml) and racked as documented below:

![Rack diagram](./assets/images/rack_architecture.drawio.svg)

Outside of what is explicitly documented [here](./hardware.yaml), I did the following:
* Replaced the thermal paste on the MS-01 nodes. The manufacturer, Minisforum, reportedly uses sparse amounts of a subpar paste between the CPU and it's cooler. Quite a few users have reported a 10*C drop in CPU temps after doing this.
* Ran a memory test for 24 hours on all the MS-01 nodes. There have been a large number of users reporting stability issues with the i9-13900H with 96 GB of DDR5 @ 5200 MT/s. This appears to be fixed in the 1.23 and 1.24 BIOS versions, but Minisforum has only provided this to a small number of customers.

# Network

The first software configuration that needs to be completed is network (switch and router) setup. As with Kubernetes itself, basically everything else in the setup process relies on having a fully configured network stack.

* [Mellanox SX6036](./setup-sx6036.md)
