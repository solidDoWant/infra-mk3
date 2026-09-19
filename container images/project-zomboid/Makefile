MAKEFLAGS += --no-print-directory
# $(realpath) splits on whitespace and this directory has a space in its name, so the usual
# `dirname $(realpath $(MAKEFILE_LIST))` does not survive here.
PROJECT_DIR := $(CURDIR)

# Steam branch to install from. `public` is whatever the current build is (B42 today), `legacy41`
# is the old B41 line, and a point release like `42.19` pins one exact build. Branch names come
# from `steamcmd +login anonymous +app_info_print 380870 +quit`.
PZ_BRANCH ?= public
# Only for a password-protected beta. Handed to the build as a secret so it stays out of the
# image history.
PZ_BRANCH_PASSWORD ?=
export PZ_BRANCH_PASSWORD
# Bump when the packaging changes (entrypoint, runtime deps, image layout) without the game build
# changing, so consumers can pick up image fixes without a branch change.
IMAGE_REVISION ?= 1
VERSION ?= $(PZ_BRANCH)-r$(IMAGE_REVISION)

# The image contains a complete Steam install of the game, so it must not be pushed anywhere
# public - same rule as the tug2 insurgency images. Point CONTAINER_REGISTRY at the private
# registry to push, e.g. CONTAINER_REGISTRY=harbor.example.com/tug2.
CONTAINER_REGISTRY ?= zomboid
CONTAINER_REPOSITORY = $(CONTAINER_REGISTRY)/project-zomboid
IMAGE = $(CONTAINER_REPOSITORY):$(VERSION)

PUSH ?= false
PUSH_ARG = $(if $(findstring t,$(PUSH)),--push,--load)

comma := ,
DOCKER_ARGS = --build-arg PZ_BRANCH="$(PZ_BRANCH)" \
	$(if $(PZ_BRANCH_PASSWORD),--secret id=pz_branch_password$(comma)env=PZ_BRANCH_PASSWORD)

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

.PHONY: all
all: image

.PHONY: image
image: Dockerfile entrypoint.sh	## Build the server image.
	docker buildx build -t "$(IMAGE)" $(PUSH_ARG) $(DOCKER_ARGS) $(EXTRA_DOCKER_ARGS) "$(PROJECT_DIR)"

.PHONY: push
push:	## Build and push the server image. Only ever to a private registry.
	@$(MAKE) image PUSH=true

.PHONY: print-image-name
print-image-name:	## Print the full name of the image.
	@echo "$(IMAGE)"

.PHONY: print-build-id
print-build-id:	## Print the Steam build ID installed in the built image.
	@docker run --rm --entrypoint /bin/bash "$(IMAGE)" -c \
		'grep -oP "\"buildid\"\s+\"\K[0-9]+" /opt/pz-server/steamapps/appmanifest_380870.acf'

##@ Local testing

# The server runs as 1000:1000 and writes everything it persists (saves, player DB, server INI,
# logs, workshop mods) here, so the directory has to be owned by that UID on the host.
LOCAL_DATA_DIR ?= $(PROJECT_DIR)/.local-data
LOCAL_ADMIN_PASSWORD ?= localadmin
LOCAL_PORT ?= 16261
# The server saves the world on shutdown, so whatever stops the container has to outwait it.
SHUTDOWN_TIMEOUT ?= 120
STOP_TIMEOUT = $(shell echo $$(( $(SHUTDOWN_TIMEOUT) + 30 )))

.PHONY: run-local
run-local:	## Run a server locally against LOCAL_DATA_DIR.
	@mkdir -p "$(LOCAL_DATA_DIR)"
	@chown 1000:1000 "$(LOCAL_DATA_DIR)" 2> /dev/null || echo "  could not chown $(LOCAL_DATA_DIR) to 1000:1000, the server may fail to write to it"
	docker run --rm -it --name project-zomboid-local \
		-p $(LOCAL_PORT):$(LOCAL_PORT)/udp \
		-p $$(( $(LOCAL_PORT) + 1 )):$$(( $(LOCAL_PORT) + 1 ))/udp \
		-v "$(LOCAL_DATA_DIR):/var/lib/zomboid" \
		-e PORT=$(LOCAL_PORT) \
		-e ADMIN_PASSWORD="$(LOCAL_ADMIN_PASSWORD)" \
		-e SHUTDOWN_TIMEOUT=$(SHUTDOWN_TIMEOUT) \
		$(EXTRA_RUN_ARGS) \
		"$(IMAGE)"

.PHONY: stop-local
stop-local:	## Stop the local server, giving it time to save first.
	docker stop -t $(STOP_TIMEOUT) project-zomboid-local

.PHONY: clean
clean:	## Remove the built image.
	@docker image rm -f "$(IMAGE)" 2> /dev/null > /dev/null || true
