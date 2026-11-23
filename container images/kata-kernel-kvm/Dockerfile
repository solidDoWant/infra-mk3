# Kata's guest kernel, built with kata's own config fragments and kernel build
# script for the kata version the nodes run, plus kvm.conf. The image holds
# only /vmlinux-kvm; the kata-kernel DaemonSet copies it onto each kata node.
ARG BUILD_IMAGE
FROM ${BUILD_IMAGE} AS build
ARG KATA_VERSION
ARG KATA_COMMIT
ARG KERNEL_VERSION
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      build-essential bc bison flex libelf-dev libssl-dev git curl ca-certificates xz-utils patch python3 cpio kmod rsync dwarves \
 && rm -rf /var/lib/apt/lists/*
RUN git clone -q --filter=blob:none --no-checkout https://github.com/kata-containers/kata-containers /kata \
 && cd /kata \
 && git -c advice.detachedHead=false checkout -q "${KATA_COMMIT}" -- tools/packaging/kernel tools/packaging/scripts \
 && test "$(git rev-parse "refs/tags/${KATA_VERSION}^{commit}" 2>/dev/null || git ls-remote origin "refs/tags/${KATA_VERSION}" | cut -f1)" = "${KATA_COMMIT}"
COPY kvm.conf /kata/tools/packaging/kernel/configs/fragments/x86_64/kvm.conf
WORKDIR /kata/tools/packaging/kernel
RUN ./build-kernel.sh -v "${KERNEL_VERSION}" setup \
 && ./build-kernel.sh -v "${KERNEL_VERSION}" build \
 && grep -qx 'CONFIG_KVM_AMD=y' kata-linux-*/.config \
 && cp kata-linux-*/vmlinux /vmlinux-kvm

FROM scratch
COPY --from=build /vmlinux-kvm /vmlinux-kvm
