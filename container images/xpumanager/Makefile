BASE_IMAGE = ubuntu:24.04
XPUMANAGER_VERSION = V1.2.41

NEW_IMAGE = ghcr.io/soliddowant/xpumanager
NEW_IMAGE_FULL = $(NEW_IMAGE):$(XPUMANAGER_VERSION:V%=%)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		--build-arg BASE_IMAGE="$(BASE_IMAGE)" \
		--build-arg XPUMANAGER_VERSION="$(XPUMANAGER_VERSION)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		--push \
		.
