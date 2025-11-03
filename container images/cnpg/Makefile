PG_VERSION = 17.6

NEW_IMAGE = ghcr.io/soliddowant/postgresql-teleport
NEW_IMAGE_FULL = $(NEW_IMAGE):$(PG_VERSION)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		-f Dockerfile.teleport \
		--build-arg PG_VERSION="$(PG_VERSION)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		--push \
		.
