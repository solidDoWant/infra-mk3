BASE_IMAGE = ubuntu:25.04
FILEFLOWS_VERSION = 25.5.9.5493
COMSKIP_VERSION = V0.83

NEW_IMAGE = ghcr.io/soliddowant/fileflows
NEW_IMAGE_FULL = $(NEW_IMAGE):$(FILEFLOWS_VERSION)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		--build-arg BASE_IMAGE="$(BASE_IMAGE)" \
		--build-arg FILEFLOWS_VERSION="$(FILEFLOWS_VERSION)" \
		--build-arg COMSKIP_VERSION="$(COMSKIP_VERSION)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		--push \
		.
