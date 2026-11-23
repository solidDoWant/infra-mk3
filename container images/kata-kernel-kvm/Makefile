BUILD_IMAGE = mirror.gcr.io/library/debian:trixie@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6
# The kata release the nodes run (Talos's kata-containers extension: `talosctl
# get extensions`), the commit its tag points at, and the kernel version in
# that release's versions.yaml (assets.kernel.version). Change all three
# together on a kata upgrade.
KATA_VERSION = 3.32.0
KATA_COMMIT = 337b6002681479fb6a605ca8a7a1138e81b6098c
KERNEL_VERSION = 6.18.35
# Bump when kvm.conf or the packaging changes without the versions changing.
IMAGE_REVISION ?= 1

NEW_IMAGE = ghcr.io/soliddowant/kata-kernel-kvm
NEW_IMAGE_FULL = $(NEW_IMAGE):$(KATA_VERSION)-$(KERNEL_VERSION)-r$(IMAGE_REVISION)

PUSH ?= true
PUSH_ARG = $(if $(findstring t,$(PUSH)),--push,--load)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		--platform linux/amd64 \
		--build-arg BUILD_IMAGE="$(BUILD_IMAGE)" \
		--build-arg KATA_VERSION="$(KATA_VERSION)" \
		--build-arg KATA_COMMIT="$(KATA_COMMIT)" \
		--build-arg KERNEL_VERSION="$(KERNEL_VERSION)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		$(PUSH_ARG) \
		.

.PHONY: print-image-name
print-image-name:
	@echo "$(NEW_IMAGE_FULL)"
