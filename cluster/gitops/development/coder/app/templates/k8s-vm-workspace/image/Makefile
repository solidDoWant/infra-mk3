PROJECT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# Collect all files that affect the VM image build
VM_IMAGE_FILES = $(shell find $(PROJECT_DIR)/os-config -type f)

CONTAINER_REGISTRY = harbor.$(shell sops -d "$(PROJECT_DIR)/../../../../../../flux-system/flux/cluster/cluster-secrets.sops.yaml" | yq '.stringData.SECRET_PUBLIC_DOMAIN_NAME')
CONTAINER_IMAGE = $(CONTAINER_REGISTRY)/coder/nixos-workspace
CONTAINER_TAGS = $(shell date +'%Y%m%d%H%M%S') latest
CONTAINER_FULL_TAGS = $(foreach TAG,$(CONTAINER_TAGS),$(CONTAINER_IMAGE):$(TAG))

PUSH_ALL ?= false

.DEFAULT_GOAL := vm-image

.PHONY: update-dependencies
update-dependencies:
	nix flake update --flake ./os-config

result: $(VM_IMAGE_FILES)
	nix build ./os-config/#kubevirt-container

.PHONY: vm-image
vm-image: update-dependencies result
	[ "$(PUSH_ALL)" = "false" ] || (	\
		$(foreach CONTAINER_FULL_TAGS,$(CONTAINER_FULL_TAGS),nix run nixpkgs#crane -- push result "$(CONTAINER_FULL_TAGS)" &&) true	\
	)

.PHONY: print-container-image
print-container-image:
	@$(foreach CONTAINER_FULL_TAGS,$(CONTAINER_FULL_TAGS),echo "$(CONTAINER_FULL_TAGS)";)

.PHONY: clean
clean:
	rm -rf result
