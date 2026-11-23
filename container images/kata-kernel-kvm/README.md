# kata-kernel-kvm

Kata's guest kernel with KVM built in, for the `kata-nested` runtime class: a container in a
`kata-nested` pod can run its own VMs, through `/dev/kvm` in the guest. vault-sync's Android
emulator CI stage needs it.

The hosts (AMD, `kvm_amd nested=1`) already pass SVM to every kata guest. Kata's stock guest kernel
has no KVM, so nothing in the guest can use it. This image is that kernel, built with kata's own
`tools/packaging/kernel/build-kernel.sh` and config fragments for the kata release the nodes run,
plus `kvm.conf`. It holds only `/vmlinux-kvm` (an uncompressed `vmlinux`, as Cloud Hypervisor
boots it).

The `kata-kernel` DaemonSet (`cluster/gitops/system-controllers/runtimes/kata-containers/`)
copies it to `/var/lib/kata-kernels/` on each kata node. There, the `kata-nested` runtime's
configuration (`talos/patches/all/27-kata.yaml`) names it as the guest kernel.

## Building

```sh
make image             # build and push to ghcr.io/soliddowant/kata-kernel-kvm
make image PUSH=false  # build and load locally
make print-image-name
```

The tag is `<kata version>-<kernel version>-r<IMAGE_REVISION>`. **On every kata upgrade** (for
example Talos 1.15's kata 4.x), update `KATA_VERSION`, `KATA_COMMIT` and `KERNEL_VERSION` together,
rebuild, and update the digest-pinned reference in the DaemonSet. A guest kernel from another kata
release may not match that release's agent and configuration.
