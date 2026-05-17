OPENARC_VERSION = v2.0.4

NEW_IMAGE = ghcr.io/soliddowant/openarc
NEW_IMAGE_FULL = $(NEW_IMAGE):$(OPENARC_VERSION:v%=%)

.PHONY: all
all: image

.PHONY: image
image:
	$$(nix build --print-out-paths --no-link .#openarc-image) | docker load
	docker tag openarc:latest $(NEW_IMAGE_FULL)
	docker push $(NEW_IMAGE_FULL)
