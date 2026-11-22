MAKEFLAGS += --no-print-directory
# This directory has a space in its parent's name, so no $(realpath) here.
CONTAINER_REGISTRY ?= ghcr.io/soliddowant
CONTAINER_REPOSITORY = $(CONTAINER_REGISTRY)/ci-tools
# Content-addressed: the same tree always gets the same tag, and the shared
# Pipelines pin the pushed image by digest anyway.
VERSION ?= $(shell git ls-files -s . | sha256sum | cut -c1-12)
IMAGE = $(CONTAINER_REPOSITORY):$(VERSION)
# The workspace for the e2e test's fixture checkouts: dockerd must see it at
# the same path (the Tekton Task's workspace).
E2E_WORKSPACE ?= $(CURDIR)/.e2e

##@ General
.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build
.PHONY: image
image: ## Build the ci-tools image.
	docker build -t "$(IMAGE)" .

.PHONY: push
push: image ## Build and push the image, and print its digest reference.
	docker push "$(IMAGE)"
	@echo "pushed: $$(docker inspect --format '{{index .RepoDigests 0}}' "$(IMAGE)")"

.PHONY: print-image-name
print-image-name: ## Print the image name and tag.
	@echo "$(IMAGE)"

##@ Test
.PHONY: test
test: image ## Run the unit tests and shellcheck in the image.
	docker run --rm "$(IMAGE)" /ci-tools/tests/run.sh

.PHONY: e2e
e2e: image ## Run the fixture project through ci-stages and a dry-run ci-release (needs CI_REPO and a Tekton docker Task).
	tests/e2e.sh "$(IMAGE)" "$(E2E_WORKSPACE)"
