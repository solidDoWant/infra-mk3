FROM mcr.microsoft.com/devcontainers/base:ubuntu26.04@sha256:91eff046d5c12318fc98e59258982b87ba896c467427ed8b5dab5a02107a5db7

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
ARG TELEPORT_VERSION=18.11.7
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
COPY --from=mikefarah/yq:4.54.1@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e /usr/bin/yq /usr/local/bin/yq

# gomplate
COPY --from=hairyhenderson/gomplate:stable@sha256:9c73c3cacc598cc9d926c67c5548901a4a4ee2223d29a2dacc910a68a5dfd684 /gomplate /usr/local/bin/gomplate

# dive
# "temporary" until https://github.com/wagoodman/dive/pull/511 is merged
COPY --from=ghcr.io/soliddowant/dive:v0.12.0-1-g5dd9ba6@sha256:ec44733c7f17587f4cd3776d604d0ec41d81dd5ece4692ea386b1cac6f45752e /usr/local/bin/dive /usr/local/bin/dive

# talosctl
COPY --from=ghcr.io/siderolabs/talosctl:v1.14.2@sha256:b655ae1c73789c4789fcf6fbd61c8f45400ed4b3bd9892a26092fcd4d8d95d86 /talosctl /usr/local/bin/talosctl

# topf
COPY --from=ghcr.io/postfinance/topf:v0.6.2@sha256:745b33c5f900df7cd9885557a037fcc5471b167b1fc20046385639112e3e6deb /usr/local/bin/topf /usr/local/bin/topf

# helmfile
COPY --from=ghcr.io/helmfile/helmfile:v1.8.2@sha256:5dbdc37016c7e286d4a1a64ac1e360cee79590df2949891823bf73618003381b /usr/local/bin/helmfile /usr/local/bin/helmfile

# kubectl
COPY --from=registry.k8s.io/kubectl:v1.37.2@sha256:fe049faa65ae483ac200009a949a68fa4c9985daea12c9cb1195c9c7965301fc /bin/kubectl /usr/local/bin/kubectl

# flux
COPY --from=ghcr.io/fluxcd/flux-cli:v2.10.0@sha256:1a5178b1770052d6e88ab1c7c8434c5ac9bca8a8ab984dcaf6b9df31814ce9f2 /usr/local/bin/flux /usr/local/bin/flux

# Coder
COPY --from=ghcr.io/coder/coder:v2.38.4@sha256:e5f4489f3fac3ee6d975552d989458b50882e78f0560d4f91253053f3797a019 /opt/coder /usr/local/bin/coder

# Terraform
COPY --from=hashicorp/terraform:1.17@sha256:4d1b496a256f2989bccdb04b9104a4ede97234b10fba90259e173e905ec4fb58 /bin/terraform /usr/local/bin/terraform

# tflint
COPY --from=ghcr.io/terraform-linters/tflint:v0.65.0@sha256:2788f4d4fc663c0e953b011b01bf443fe5bfce7587ee916e588e6057b85d6359 /usr/local/bin/tflint /usr/local/bin/tflint

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
ARG CILIUM_CLI_VERSION=v0.20.1
RUN mkdir -pv /tmp/cilium && \
    # Vars for determining download URLs
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)" && \
    curl -fsSL -o /tmp/cilium/cilium.tar.gz "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-${KERNEL}-${PRETTY_ARCH}.tar.gz" && \
    tar -xzvf /tmp/cilium/cilium.tar.gz -C /usr/local/bin cilium && \
    rm -rvf /tmp/cilium

# openspi2jsonschema CRD to schema converter
# renovate: datasource=github-tags depName=yannh/kubeconform
ARG KUBECONFORM_VERSION=v0.8.0
RUN curl -fsSL -o /usr/local/bin/openapi2jsonschema "https://raw.githubusercontent.com/yannh/kubeconform/refs/tags/${KUBECONFORM_VERSION}/scripts/openapi2jsonschema.py" && \
    chmod +x /usr/local/bin/openapi2jsonschema

# istioctl
COPY --from=istio/istioctl:1.31.3@sha256:6287ada00f31ae964f01b60e9e1ba54b9819af28589d7fe630439f99eb68d2be /usr/local/bin/istioctl /usr/local/bin/istioctl

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

# diffoci
# renovate: datasource=github-releases depName=reproducible-containers/diffoci
ARG DIFFOCI_VERSION=v0.1.8
RUN KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')" && \
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)" && \
    curl -fsSL -o /usr/local/bin/diffoci "https://github.com/reproducible-containers/diffoci/releases/download/${DIFFOCI_VERSION}/diffoci-${DIFFOCI_VERSION}.${KERNEL}-${PRETTY_ARCH}" && \
    chmod +x /usr/local/bin/diffoci

# cmtool
# renovate: datasource=github-releases depName=cert-manager/cmctl
ARG CMCTL_VERSION=v2.6.1
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
    echo "complete -C $(which terraform) terraform" | sudo tee /etc/bash_completion.d/terraform.bash > /dev/null
