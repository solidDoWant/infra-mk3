PROJECT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# Collect all files that affect the VM image build
VM_IMAGE_FILES = $(shell find $(PROJECT_DIR)/os-config -type f)

CONTAINER_REGISTRY = harbor.$(shell sops -d "$(PROJECT_DIR)/../../../../../../flux-system/flux/cluster/cluster-secrets.sops.yaml" | yq '.stringData.SECRET_PUBLIC_DOMAIN_NAME')

# Two image variants, built from the same os-config (see os-config/flake.nix):
# the base workspace, and the same plus a headless Xfce desktop served over
# Teleport. They are separate images because the desktop is baked into the
# system closure and adds several GB that non-desktop workspaces should not have
# to import. Both are pinned by tag in the template (template/kubernetes.tf).
CONTAINER_IMAGE = $(CONTAINER_REGISTRY)/coder/nixos-workspace
CONTAINER_IMAGE_DESKTOP = $(CONTAINER_IMAGE)-desktop
# `:=` is load-bearing: with a recursive `=` the $(shell date) re-runs on every
# reference, so the two variants (and `print-container-image` vs the actual push)
# would end up with different timestamps. The template pins ONE image_version for
# both variants, so they have to share a tag.
CONTAINER_TAGS := $(shell date +'%Y%m%d%H%M%S') latest
CONTAINER_FULL_TAGS := $(foreach TAG,$(CONTAINER_TAGS),$(CONTAINER_IMAGE):$(TAG))
CONTAINER_FULL_TAGS_DESKTOP := $(foreach TAG,$(CONTAINER_TAGS),$(CONTAINER_IMAGE_DESKTOP):$(TAG))

PUSH_ALL ?= false

.DEFAULT_GOAL := vm-image

.PHONY: update-dependencies
update-dependencies:
	nix flake update --flake ./os-config

result: $(VM_IMAGE_FILES)
	nix build ./os-config/#kubevirt-container

result-desktop: $(VM_IMAGE_FILES)
	nix build ./os-config/#kubevirt-container-desktop --out-link result-desktop

.PHONY: vm-image
vm-image: update-dependencies result result-desktop
	[ "$(PUSH_ALL)" = "false" ] || (	\
		$(foreach CONTAINER_FULL_TAGS,$(CONTAINER_FULL_TAGS),nix run nixpkgs#crane -- push result "$(CONTAINER_FULL_TAGS)" &&)	\
		$(foreach CONTAINER_FULL_TAGS_DESKTOP,$(CONTAINER_FULL_TAGS_DESKTOP),nix run nixpkgs#crane -- push result-desktop "$(CONTAINER_FULL_TAGS_DESKTOP)" &&) true	\
	)

.PHONY: print-container-image
print-container-image:
	@$(foreach CONTAINER_FULL_TAGS,$(CONTAINER_FULL_TAGS),echo "$(CONTAINER_FULL_TAGS)";)
	@$(foreach CONTAINER_FULL_TAGS_DESKTOP,$(CONTAINER_FULL_TAGS_DESKTOP),echo "$(CONTAINER_FULL_TAGS_DESKTOP)";)

.PHONY: clean
clean:
	rm -rf result result-desktop
