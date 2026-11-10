FROM mcr.microsoft.com/devcontainers/base:ubuntu26.04@sha256:b1e3b08610ae0b2599f57c3a492eebc93d1d26dbaefb4a0bad0caa7149e4ec95

# Generally helpful tools
RUN apt update && apt install --no-install-recommends -y \
    file sshpass minicom age whois yq iputils-ping p7zip \
    xorriso parted dosfstools mtools dnsutils redis-tools \
    inotify-tools uuid-runtime postgresql-common

# Install debs from sources that don't provide an apt repo
# renovate: datasource=github-releases depName=go-task/task
ARG TASK_VERSION=v3.54.0
# renovate: datasource=github-releases depName=getsops/sops
ARG SOPS_VERSION=v3.13.3
# renovate: datasource=docker depName=public.ecr.aws/gravitational/teleport-distroless
ARG TELEPORT_VERSION=18.11.8
RUN mkdir -pv /tmp/debs && \
    # Vars for determining download URLs
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)" && \
    # Taskfile
    curl -fsSL -o /tmp/debs/taskfile.deb "https://github.com/go-task/task/releases/download/${TASK_VERSION}/task_${TASK_VERSION#v}_${KERNEL}_${PRETTY_ARCH}.deb" && \
    # SOPS
    curl -fsSL -o /tmp/debs/sops.deb "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops_${SOPS_VERSION#v}_${PRETTY_ARCH}.deb" && \
    # Teleport
    curl -fsSL -o /tmp/debs/teleport.deb "https://cdn.teleport.dev/teleport_${TELEPORT_VERSION}_${PRETTY_ARCH}.deb" && \
    dpkg -i /tmp/debs/*.deb && \
    rm -rvf /tmp/debs

# Postgres APT repo
# Some tools (i.e. pg_dump) must have a version newer than or equal to the postgres server version. Ubuntu "Plucky" or newer is needed
# for postgresql-client-17, so use the postgres APT repo instead
RUN /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y && \
    apt install --no-install-recommends -y postgresql-client-17

# Needed for BIOS and iDRAC config
COPY install-racadm.sh /tmp/install-racadm.sh
RUN /tmp/install-racadm.sh

# yq
COPY --from=mikefarah/yq:4.54.3@sha256:7834187596ad56fd5a81436114e0b0b9dd54c91bb43946d1f7145b2be5f9c3d2 /usr/bin/yq /usr/local/bin/yq

# gomplate
COPY --from=hairyhenderson/gomplate:stable@sha256:9c73c3cacc598cc9d926c67c5548901a4a4ee2223d29a2dacc910a68a5dfd684 /gomplate /usr/local/bin/gomplate

# dive
# "temporary" until https://github.com/wagoodman/dive/pull/511 is merged
COPY --from=ghcr.io/soliddowant/dive:v0.12.0-1-g5dd9ba6@sha256:ec44733c7f17587f4cd3776d604d0ec41d81dd5ece4692ea386b1cac6f45752e /usr/local/bin/dive /usr/local/bin/dive

# talosctl
COPY --from=ghcr.io/siderolabs/talosctl:v1.14.5@sha256:0b852e35c1f513ee5eacc22183d6193486012420569fde39fcd5260c51938443 /talosctl /usr/local/bin/talosctl

# topf
COPY --from=ghcr.io/postfinance/topf:v0.6.2@sha256:745b33c5f900df7cd9885557a037fcc5471b167b1fc20046385639112e3e6deb /usr/local/bin/topf /usr/local/bin/topf

# helmfile
COPY --from=ghcr.io/helmfile/helmfile:v1.8.3@sha256:4b48dff9278362abea796067eea5b8f9682d101431403a7de50ca4fab82265f4 /usr/local/bin/helmfile /usr/local/bin/helmfile

# kubectl
COPY --from=registry.k8s.io/kubectl:v1.37.2@sha256:fe049faa65ae483ac200009a949a68fa4c9985daea12c9cb1195c9c7965301fc /bin/kubectl /usr/local/bin/kubectl

# flux
COPY --from=ghcr.io/fluxcd/flux-cli:v2.10.0@sha256:1a5178b1770052d6e88ab1c7c8434c5ac9bca8a8ab984dcaf6b9df31814ce9f2 /usr/local/bin/flux /usr/local/bin/flux

# Coder
COPY --from=ghcr.io/coder/coder:v2.39.0@sha256:5fb8f624dc0d33be89c72c7b2e384cdc7c2c5ac0d5847348d3aa0edaf058605c /opt/coder /usr/local/bin/coder

# Terraform
COPY --from=hashicorp/terraform:1.17@sha256:a5d5a5a892c98f60fcbfa81eac2a40fc19e7b3fa7719bccae10ff6111d22524a /bin/terraform /usr/local/bin/terraform

# tflint
COPY --from=ghcr.io/terraform-linters/tflint:v0.66.0@sha256:65b9944a9274c4989492c1d79998c2801664bf8a55fddb4bd3a9e6d73a006ddc /usr/local/bin/tflint /usr/local/bin/tflint

# Helm
ENV HELM_DATA_HOME=/usr/local/share/helm
COPY --from=alpine/helm:4.3.1@sha256:e3f8d5c462d75470fbb1fce79ad5c20063657096d1f98c0fcea869e2600e2e5e /usr/bin/helm /usr/local/bin/helm
## Plugins
### helm-diff: required by `helmfile apply`
### Helm 4 verifies plugins by default; git-sourced installs carry no provenance
# renovate: datasource=github-releases depName=databus23/helm-diff
ARG HELM_DIFF_VERSION=v3.15.15
RUN helm plugin install --verify=false https://github.com/databus23/helm-diff --version "${HELM_DIFF_VERSION}"

# kustomize
COPY --from=registry.k8s.io/kustomize/kustomize:v5.8.3@sha256:429eda4a1c76a7de458d0c4ca3ded9b5d764899ff6bdaeccc1d98b1b6ee873e4 /app/kustomize /usr/local/bin/kustomize

# Cilium CLI
# renovate: datasource=github-releases depName=cilium/cilium-cli
ARG CILIUM_CLI_VERSION=v0.20.2
RUN mkdir -pv /tmp/cilium && \
    # Vars for determining download URLs
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)" && \
    curl -fsSL -o /tmp/cilium/cilium.tar.gz "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-${KERNEL}-${PRETTY_ARCH}.tar.gz" && \
    tar -xzvf /tmp/cilium/cilium.tar.gz -C /usr/local/bin cilium && \
    rm -rvf /tmp/cilium

# toolgate CLI (MCP gateway client: `toolgate login`, secrets, workspace defaults)
# renovate: datasource=github-releases depName=solidDoWant/toolgate
ARG TOOLGATE_VERSION=0.4.9
RUN mkdir -pv /tmp/toolgate && \
    # Vars for determining download URLs
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; 'aarch64') echo "arm64";; *) uname -m;; esac)" && \
    curl -fsSL -o "/tmp/toolgate/toolgate-${KERNEL}-${PRETTY_ARCH}" "https://github.com/solidDoWant/toolgate/releases/download/${TOOLGATE_VERSION}/toolgate-${KERNEL}-${PRETTY_ARCH}" && \
    curl -fsSL -o /tmp/toolgate/checksums.txt "https://github.com/solidDoWant/toolgate/releases/download/${TOOLGATE_VERSION}/checksums.txt" && \
    (cd /tmp/toolgate && grep " toolgate-${KERNEL}-${PRETTY_ARCH}\$" checksums.txt | sha256sum -c -) && \
    install -m 0755 "/tmp/toolgate/toolgate-${KERNEL}-${PRETTY_ARCH}" /usr/bin/toolgate && \
    rm -rvf /tmp/toolgate

# openspi2jsonschema CRD to schema converter
# renovate: datasource=github-tags depName=yannh/kubeconform
ARG KUBECONFORM_VERSION=v0.8.0
RUN curl -fsSL -o /usr/local/bin/openapi2jsonschema "https://raw.githubusercontent.com/yannh/kubeconform/refs/tags/${KUBECONFORM_VERSION}/scripts/openapi2jsonschema.py" && \
    chmod +x /usr/local/bin/openapi2jsonschema

# istioctl
COPY --from=istio/istioctl:1.31.4@sha256:a95d863708d2d19c3ce4ec498b9e1f35c241b6be3d008cee49ccf5c7968fc46f /usr/local/bin/istioctl /usr/local/bin/istioctl

# flux-local
# RUN pipx install --include-deps flux-local

# krew
ENV KREW_ROOT=/usr/local/krew
# renovate: datasource=github-releases depName=kubernetes-sigs/krew
ARG KREW_VERSION=v0.5.0
RUN mkdir -pv /tmp/krew && \
    # Vars for determining download URLs
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)" && \
    KREW_FILE_NAME="krew-${KERNEL}_${PRETTY_ARCH}" && \
    curl -fsSL -o /tmp/krew/krew.tar.gz "https://github.com/kubernetes-sigs/krew/releases/download/${KREW_VERSION}/krew-${KERNEL}_${PRETTY_ARCH}.tar.gz" && \
    tar -xzvf /tmp/krew/krew.tar.gz -C /tmp/krew "./${KREW_FILE_NAME}" && \
    "/tmp/krew/${KREW_FILE_NAME}" install krew && \
    rm -rvf /tmp/krew
ENV PATH="${KREW_ROOT}/bin:${PATH}"

## Krew plugins
RUN kubectl krew update && \
    kubectl krew install kyverno cnpg sniff virt

## Krew ownership fix
RUN find /usr/local/krew -type d -exec chmod 777 {} \; && \
    find /usr/local/krew -type f -exec chmod ugo+w {} \;

# krr (Kubernetes resource recommender)
# Not in the krew index. The release is a PyInstaller bundle (binary + _internal/), amd64 only.
# `krr` on PATH is a wrapper that port-forwards to vmselect (krr can't auth to the
# apiserver proxy with client certs). Also linked as kubectl-krr so `kubectl krr` works.
# renovate: datasource=github-releases depName=robusta-dev/krr
ARG KRR_VERSION=v1.31.3
RUN mkdir -pv /tmp/krr && \
    curl -fsSL -o /tmp/krr/krr.zip "https://github.com/robusta-dev/krr/releases/download/${KRR_VERSION}/krr-ubuntu-latest-${KRR_VERSION}.zip" && \
    unzip -q /tmp/krr/krr.zip -d /opt && \
    rm -rvf /tmp/krr
COPY --chmod=755 krr-wrapper.sh /usr/local/bin/krr
RUN ln -sfv /usr/local/bin/krr /usr/local/bin/kubectl-krr

# diffoci
# renovate: datasource=github-releases depName=reproducible-containers/diffoci
ARG DIFFOCI_VERSION=v0.1.8
RUN KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)" && \
    curl -fsSL -o /usr/local/bin/diffoci "https://github.com/reproducible-containers/diffoci/releases/download/${DIFFOCI_VERSION}/diffoci-${DIFFOCI_VERSION}.${KERNEL}-${PRETTY_ARCH}" && \
    chmod +x /usr/local/bin/diffoci

# cmtool
# renovate: datasource=github-releases depName=cert-manager/cmctl
ARG CMCTL_VERSION=v2.6.2
RUN KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)" && \
    curl -fsSL -o /usr/local/bin/cmtool "https://github.com/cert-manager/cmctl/releases/download/${CMCTL_VERSION}/cmctl_${KERNEL}_${PRETTY_ARCH}" && \
    chmod +x /usr/local/bin/cmtool

# Nix
RUN curl -fsSL https://nixos.org/releases/nix/nix-install.sh | sh -s -- --daemon && \
    mkdir -p /etc/nix && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf && \
    echo "system-features = nixos-test benchmark big-parallel kvm" >> /etc/nix/nix.conf

# SOPS configuration
ENV SOPS_AGE_KEY_FILE=keys/primary.key

# Taskfile experiments
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
    topf completion bash | sudo tee /etc/bash_completion.d/topf.bash > /dev/null && \
    helmfile completion bash | sudo tee /etc/bash_completion.d/helmfile.bash > /dev/null && \
    kubectl completion bash | sudo tee /etc/bash_completion.d/kubectl.bash > /dev/null && \
    helm completion bash | sudo tee /etc/bash_completion.d/helm.bash > /dev/null && \
    kustomize completion bash | sudo tee /etc/bash_completion.d/kustomize.bash > /dev/null && \
    cilium completion bash | sudo tee /etc/bash_completion.d/cilium.bash > /dev/null && \
    flux completion bash | sudo tee /etc/bash_completion.d/flux.bash > /dev/null && \
    istioctl completion bash | sudo tee /etc/bash_completion.d/istioctl.bash > /dev/null && \
    diffoci completion bash | sudo tee /etc/bash_completion.d/diffoci.bash > /dev/null && \
    docker completion bash | sudo tee /etc/bash_completion.d/docker.bash > /dev/null && \
    cmtool completion bash | sudo tee /etc/bash_completion.d/cmtool.bash > /dev/null && \
    coder completion -s bash | sudo tee /etc/bash_completion.d/coder.bash > /dev/null && \
    # krr's PyInstaller bundle lacks shellingham.posix, so shell auto-detection crashes; skip it
    _TYPER_COMPLETE_TEST_DISABLE_SHELL_DETECTION=1 krr --show-completion bash | sudo tee /etc/bash_completion.d/krr.bash > /dev/null && \
    echo "complete -C $(which terraform) terraform" | sudo tee /etc/bash_completion.d/terraform.bash > /dev/null
