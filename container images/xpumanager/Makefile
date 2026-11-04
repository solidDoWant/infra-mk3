BASE_IMAGE = public.ecr.aws/docker/library/ubuntu:26.04@sha256:6a06111c3b0a8600feadb270aec771dc239bf407b25625f93f44ab00e11f4d3c
# renovate: datasource=github-releases depName=intel/xpumanager
XPUMANAGER_VERSION = v2.3.0

NEW_IMAGE = ghcr.io/soliddowant/xpumanager
NEW_IMAGE_FULL = $(NEW_IMAGE):$(XPUMANAGER_VERSION:v%=%)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		--build-arg BASE_IMAGE="$(BASE_IMAGE)" \
		--build-arg XPUMANAGER_VERSION="$(XPUMANAGER_VERSION)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		--push \
		.
