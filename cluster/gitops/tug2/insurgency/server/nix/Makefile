PROJECT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# Collect all files that affect the VM image build
VM_IMAGE_FILES = $(shell find $(PROJECT_DIR)/os-config -type f)

CONTAINER_REGISTRY = harbor.$(shell sops -d "$(PROJECT_DIR)/../../../../flux-system/flux/cluster/cluster-secrets.sops.yaml" | yq '.stringData.SECRET_PUBLIC_DOMAIN_NAME')
CONTAINER_IMAGE = $(CONTAINER_REGISTRY)/tug2/insurgency-server-os
CONTAINER_TAGS = $(shell date +'%Y%m%d%H%M%S') latest
CONTAINER_FULL_TAGS = $(foreach TAG,$(CONTAINER_TAGS),$(CONTAINER_IMAGE):$(TAG))

VM_POOL_NAME = insurgency-server
NAMESPACE = tug2
VM_NAME = $(VM_POOL_NAME)-0

PUSH_ALL ?= false

.DEFAULT_GOAL := vm-image

.PHONY: update-dependencies
update-dependencies:
	nix flake update --flake ./os-config

result: $(VM_IMAGE_FILES)
	nix build ./os-config/#kubevirt-container

.PHONY: vm-image
vm-image: # update-dependencies result
	[ "$(PUSH_ALL)" = "false" ] || (	\
		$(foreach CONTAINER_FULL_TAGS,$(CONTAINER_FULL_TAGS),nix run nixpkgs#crane -- push result "$(CONTAINER_FULL_TAGS)" &&) true	\
	)

.PHONY: restart-vm-pool
restart-vm-pool:
	kubectl scale -n "$(NAMESPACE)" vmpool "$(VM_POOL_NAME)" --replicas=0
	kubectl wait --for=delete -n "$(NAMESPACE)" vm "$(VM_NAME)" --timeout=120s
	TELEPORT_NODE_NAME=$$(tsh ls -f json | jq -r --arg VM_NAME "$(VM_NAME)" 'map(select(.spec.hostname == $$VM_NAME)) | first | .metadata.name // ""') && \
	if [ -n "$${TELEPORT_NODE_NAME}" ] ; then \
		echo "Removing Teleport node: $${TELEPORT_NODE_NAME}" ; \
	  	tctl rm node/"$${TELEPORT_NODE_NAME}" ; \
	fi
	kubectl scale -n "$(NAMESPACE)" vmpool "$(VM_POOL_NAME)" --replicas=1
	kubectl wait --for=condition=Ready -n "$(NAMESPACE)" vm "$(VM_NAME)" --timeout=300s

.PHONY: remote-console
remote-console:
	@exec kubectl virt console -n "$(NAMESPACE)" "$(VM_NAME)"

.PHONY: teleport-console
teleport-console:
	@exec tsh ssh root@"$(VM_NAME)"

.PHONY: print-container-image
print-container-image:
	@$(foreach CONTAINER_FULL_TAGS,$(CONTAINER_FULL_TAGS),echo "$(CONTAINER_FULL_TAGS)";)

.PHONY: clean
clean:
	rm -rf result
