BASE_IMAGE = ubuntu:25.04
IMAGE_TAG = latest

NEW_IMAGE = ghcr.io/soliddowant/gateway-router
NEW_IMAGE_FULL = $(NEW_IMAGE):$(IMAGE_TAG)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		--build-arg BASE_IMAGE="$(BASE_IMAGE)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		--push \
		.
