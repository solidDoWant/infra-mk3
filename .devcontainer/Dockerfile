FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Generally helpful tools
RUN apt update && apt install --no-install-recommends -y \
    file sshpass minicom age whois yq iputils-ping p7zip \
    xorriso parted dosfstools mtools dnsutils

# Install debs from sources that don't provide an apt repo
RUN mkdir -pv /tmp/debs && \
    # Vars for determining download URLs
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)" && \
    # Taskfile
    curl -fsSL -o /tmp/debs/taskfile.deb "https://github.com/go-task/task/releases/download/v3.39.2/task_${KERNEL}_${PRETTY_ARCH}.deb" && \
    # SOPS
    curl -fsSL -o /tmp/debs/sops.deb "https://github.com/getsops/sops/releases/download/v3.9.0/sops_3.9.0_${PRETTY_ARCH}.deb" && \
    dpkg -i /tmp/debs/*.deb && \
    rm -rvf /tmp/debs

# Needed for BIOS and iDRAC config
COPY install-racadm.sh /tmp/install-racadm.sh
RUN /tmp/install-racadm.sh

# yq
COPY --from=mikefarah/yq:4.44.3 /usr/bin/yq /usr/local/bin/yq

# gomplate
COPY --from=hairyhenderson/gomplate:stable /gomplate /usr/local/bin/gomplate

# dive
COPY --from=wagoodman/dive:v0.12.0 /usr/local/bin/dive /usr/local/bin/dive

# talosctl
RUN curl -fsSL -o /usr/local/bin/talosctl https://github.com/siderolabs/talos/releases/download/v1.8.1/talosctl-linux-amd64 && \
    chmod +x /usr/local/bin/talosctl

# talhelper
COPY --from=ghcr.io/budimanjojo/talhelper:v3.0.7 /bin/talhelper /usr/local/bin/talhelper

# helmfile
COPY --from=ghcr.io/helmfile/helmfile:v1.0.0-rc.7 /usr/local/bin/helmfile /usr/local/bin/helmfile

# kubectl
COPY --from=bitnami/kubectl:1.31.2 /opt/bitnami/kubectl/bin/kubectl /usr/local/bin/kubectl

# flux
COPY --from=ghcr.io/fluxcd/flux-cli:v2.4.0 /usr/local/bin/flux /usr/local/bin/flux

# Helm
ENV HELM_DATA_HOME=/usr/local/share/helm
COPY --from=alpine/helm:3.16.2 /usr/bin/helm /usr/local/bin/helm
## Plugins
### Required for helmfile
RUN helm plugin install https://github.com/jkroepke/helm-secrets --version v4.6.2 && \
    helm plugin install https://github.com/databus23/helm-diff --version v3.9.11

# kustomize
COPY --from=registry.k8s.io/kustomize/kustomize:v5.0.0 /app/kustomize /usr/local/bin/kustomize

# Cilium CLI
RUN mkdir -pv /tmp/cilium && \
    # Vars for determining download URLs
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)" && \
    curl -fsSL -o /tmp/cilium/cilium.tar.gz "https://github.com/cilium/cilium-cli/releases/download/v0.16.19/cilium-${KERNEL}-${PRETTY_ARCH}.tar.gz" && \
    tar -xzvf /tmp/cilium/cilium.tar.gz -C /usr/local/bin cilium && \
    rm -rvf /tmp/cilium

# openspi2jsonschema CRD to schema converter
RUN curl -fsSL -o /usr/local/bin/openapi2jsonschema https://raw.githubusercontent.com/yannh/kubeconform/refs/tags/v0.6.7/scripts/openapi2jsonschema.py && \
    chmod +x /usr/local/bin/openapi2jsonschema

# istioctl
COPY --from=istio/istioctl:1.23.3 /usr/local/bin/istioctl /usr/local/bin/istioctl

# SOPS configuration
ENV SOPS_AGE_KEY_FILE=keys/primary.key

# Taskfile experiments
ENV TASK_X_MAP_VARIABLES=2
ENV TASK_X_ENV_PRECEDENCE=1

# Ansible vars
# This is needed for WSL-backed Docker because the file is world-writable
ENV ANSIBLE_CONFIG=./ansible.cfg

# Talosctl configuration
ENV TALOSCONFIG=talos/talosconfig

# Autocomplete
RUN \
    yq completion bash | sudo tee /etc/bash_completion.d/yq.bash > /dev/null && \
    talosctl completion bash | sudo tee /etc/bash_completion.d/talosctl.bash > /dev/null && \
    talhelper completion bash | sudo tee /etc/bash_completion.d/talhelper.bash > /dev/null && \
    helmfile completion bash | sudo tee /etc/bash_completion.d/helmfile.bash > /dev/null && \
    kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl.bash > /dev/null && \
    helm completion bash | sudo tee /etc/bash_completion.d/helm.bash > /dev/null && \
    kustomize completion bash | sudo tee /etc/bash_completion.d/kustomize.bash > /dev/null && \
    cilium completion bash | sudo tee /etc/bash_completion.d/cilium.bash > /dev/null && \
    flux completion bash | sudo tee /etc/bash_completion.d/flux.bash > /dev/null
