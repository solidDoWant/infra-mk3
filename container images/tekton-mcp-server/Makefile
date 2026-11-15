BUILD_IMAGE = public.ecr.aws/docker/library/golang:1.26.11-alpine3.24@sha256:ae52b5bc6ed045a9ed26ab03dc19327a802a9cc9aa8b27ed57f5c6b60579b0bb
# Upstream has no releases or tags yet, so this follows main by commit.
# renovate: datasource=git-refs depName=tektoncd/mcp-server branch=main
MCP_SERVER_COMMIT = 69b3ccf359d7375baf1bcb3b06b74d39be583b20
# Bump when the packaging changes without the upstream commit changing.
IMAGE_REVISION ?= 1

NEW_IMAGE = ghcr.io/soliddowant/tekton-mcp-server
NEW_IMAGE_FULL = $(NEW_IMAGE):0.0.0-$(shell echo $(MCP_SERVER_COMMIT) | cut -c1-7)-r$(IMAGE_REVISION)

PUSH ?= true
PUSH_ARG = $(if $(findstring t,$(PUSH)),--push,--load)

.PHONY: all
all: image

.PHONY: image
image:
	@docker buildx build \
		--build-arg BUILD_IMAGE="$(BUILD_IMAGE)" \
		--build-arg MCP_SERVER_COMMIT="$(MCP_SERVER_COMMIT)" \
		-t "$(NEW_IMAGE_FULL)" \
		--progress plain \
		$(PUSH_ARG) \
		.

.PHONY: print-image-name
print-image-name:
	@echo "$(NEW_IMAGE_FULL)"
