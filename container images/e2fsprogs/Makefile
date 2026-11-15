BUILD_IMAGE = public.ecr.aws/docker/library/alpine:3.24@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf
# renovate: datasource=github-tags depName=tytso/e2fsprogs
E2FSPROGS_VERSION = v1.47.4
# Commit the tag above points at. Update it together with the version.
E2FSPROGS_COMMIT = 7ee1d505ef3b37831215f490411f346fe57e9053
# Bump when the packaging changes without the upstream version changing.
IMAGE_REVISION ?= 1

NEW_IMAGE = ghcr.io/soliddowant/e2fsprogs
NEW_IMAGE_FULL = $(NEW_IMAGE):$(E2FSPROGS_VERSION:v%=%)-r$(IMAGE_REVISION)

PUSH ?= true
PUSH_ARG = $(if $(findstring t,$(PUSH)),--push,--load)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		--build-arg BUILD_IMAGE="$(BUILD_IMAGE)" \
		--build-arg E2FSPROGS_VERSION="$(E2FSPROGS_VERSION)" \
		--build-arg E2FSPROGS_COMMIT="$(E2FSPROGS_COMMIT)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		$(PUSH_ARG) \
		.

.PHONY: print-image-name
print-image-name:
	@echo "$(NEW_IMAGE_FULL)"
