BASE_IMAGE_FULL = revenz/fileflows:25.05-modded@sha256:c6264e0bc9d071b4f28c8564f839eda02a6eb8511f96242a54e20c3c6d48b466
BASE_IMAGE = $(word 1,$(subst :, ,$(BASE_IMAGE_FULL)))
BASE_IMAGE_TAG_FULL = $(subst $(BASE_IMAGE):,,$(BASE_IMAGE_FULL))
BASE_IMAGE_TAG = $(word 1,$(subst @, ,$(BASE_IMAGE_TAG_FULL)))

NEW_IMAGE = ghcr.io/soliddowant/fileflows
NEW_IMAGE_FULL = $(NEW_IMAGE):$(BASE_IMAGE_TAG)

.PHONY: image
image:
	@docker buildx build --build-arg BASE_IMAGE="$(BASE_IMAGE_FULL)" -t "$(NEW_IMAGE_FULL)" --push .

.PHONY: all
all: image
