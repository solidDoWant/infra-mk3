BUILD_IMAGE = public.ecr.aws/docker/library/golang:1.27.3-trixie@sha256:1896654cfc5c2b5ad74c07f29cb36f5d2d1cbed42e3054070fbfe444e521e83c
# renovate: datasource=github-tags depName=couchgres/couchgres
COUCHGRES_VERSION = v1.0.0
# Commit the tag above points at. Update it together with the version.
COUCHGRES_COMMIT = f35b7817318e86f2cf355ab45e8226a316f8085d
# Bump when the packaging changes without the upstream version changing.
IMAGE_REVISION ?= 1

NEW_IMAGE = ghcr.io/soliddowant/couchgres
NEW_IMAGE_FULL = $(NEW_IMAGE):$(COUCHGRES_VERSION:v%=%)-r$(IMAGE_REVISION)

PUSH ?= true
PUSH_ARG = $(if $(findstring t,$(PUSH)),--push,--load)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		--build-arg BUILD_IMAGE="$(BUILD_IMAGE)" \
		--build-arg COUCHGRES_VERSION="$(COUCHGRES_VERSION)" \
		--build-arg COUCHGRES_COMMIT="$(COUCHGRES_COMMIT)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		$(PUSH_ARG) \
		.

.PHONY: print-image-name
print-image-name:
	@echo "$(NEW_IMAGE_FULL)"
