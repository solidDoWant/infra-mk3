# Deno development ends around 2026-10 + 1 year (deno.com/blog/cloudflare), but upstream is
# Deno-native (Deno.* APIs, Deno localStorage checkpoints). Move runtimes when upstream does:
# https://github.com/vrtmrz/livesync-bridge/issues/84 (maintainer is evaluating Node 26).
BASE_IMAGE = mirror.gcr.io/denoland/deno:debian-2.9.7@sha256:fa335acdf6b72106eda2cb6a8cb5f4187e7630e357467489db4b2e7352d5e432
# Upstream has no releases or tags, so pin a commit on main.
# renovate: datasource=git-refs depName=vrtmrz/livesync-bridge branch=main
LIVESYNC_BRIDGE_COMMIT = fc0e028d33b3a12ddee1322951375e05107edc55
# Bump when the packaging (wrapper, healthcheck) changes without the upstream commit changing.
IMAGE_REVISION ?= 1

NEW_IMAGE = ghcr.io/soliddowant/livesync-bridge
NEW_IMAGE_FULL = $(NEW_IMAGE):$(shell echo $(LIVESYNC_BRIDGE_COMMIT) | cut -c1-7)-r$(IMAGE_REVISION)

PUSH ?= true
PUSH_ARG = $(if $(findstring t,$(PUSH)),--push,--load)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		--build-arg BASE_IMAGE="$(BASE_IMAGE)" \
		--build-arg LIVESYNC_BRIDGE_COMMIT="$(LIVESYNC_BRIDGE_COMMIT)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		$(PUSH_ARG) \
		.

.PHONY: print-image-name
print-image-name:
	@echo "$(NEW_IMAGE_FULL)"
