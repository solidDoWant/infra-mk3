# What is this?

This directory hold temporary "tooling" manifests for debugging issues. These are intended to be deployed via `kubectl apply -f`, and managed manually.

## Tools

### admin-pod

Pod with a single Ubuntu container that effectively runs as if it was in the root namespace(s), as root user. Used to debug Talos issues.

### goxdp

Basic deployment of [goxdp](https://github.com/ahsifer/goxdp). Used only as a test program to debug XDP load issues.

### iperf3

Runs four [iperf3](https://github.com/esnet/iperf) servers and clients to test network throughput. Different ports are used to test bonded link traffic sharing. This will eat all bandwidth if left running.