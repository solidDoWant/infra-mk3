BASE_IMAGE = ubuntu:25.04
FILEFLOWS_VERSION = 25.10.1.5977
COMSKIP_VERSION = V0.83
VIDEO2X_VERSION = 6.4.0

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
		--build-arg VIDEO2X_VERSION="$(VIDEO2X_VERSION)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		--push \
		.
