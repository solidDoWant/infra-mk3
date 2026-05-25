# Tracks the upstream commit pinned in flake.nix (currently main HEAD).
# Update both together; the short SHA is what shows up in the image tag.
OPENARC_VERSION = main-7de77a45
# Bump when the build logic changes (extraCommands, env, deps) — distinct
# from OPENARC_VERSION so consumers can pick up packaging fixes without
# waiting on upstream.
IMAGE_REVISION = 3

NEW_IMAGE = ghcr.io/soliddowant/openarc
NEW_IMAGE_FULL = $(NEW_IMAGE):$(OPENARC_VERSION)-r$(IMAGE_REVISION)

.PHONY: all
all: image

.PHONY: image
image:
	$$(nix build --print-out-paths --no-link .#openarc-image) | docker load
	docker tag openarc:latest $(NEW_IMAGE_FULL)
	docker push $(NEW_IMAGE_FULL)
