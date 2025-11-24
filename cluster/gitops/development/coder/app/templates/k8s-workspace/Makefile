PROJECT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

VERSION = 0.0.1-dev
TEMPLATE_NAME = k8s-workspace
ORGANIZATION = coder

.PHONY: fmt
fmt:
	@echo "Formatting Terraform configuration..."
	terraform fmt -recursive

.PHONY: lint
lint: fmt validate
	@echo "Linting Terraform configuration..."
	tflint --recursive

.PHONY: validate
validate: fmt
	@echo "Validating Terraform configuration..."
	terraform validate

.PHONY: plan
plan: fmt validate
	@echo "Creating Terraform plan..."
	KUBE_CONFIG_PATH="$${HOME}/.kube/config" \
	terraform plan

.PHONY: publish
publish: ACTIVATE_FLAG=$(if $(findstring -,$(VERSION)),,--activate)
publish: MESSAGE=v$(VERSION)
publish: plan
	@echo "Publishing version $(VERSION)..."
	coder templates push "$(TEMPLATE_NAME)" \
		--org "$(ORGANIZATION)" \
		--directory "$(PROJECT_DIR)" \
		--message "$(MESSAGE)" \
		--name "$(VERSION)"	\
		$(ACTIVATE_FLAG)