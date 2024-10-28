FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Generally helpful tools
RUN apt update && apt install --no-install-recommends -y \
    file sshpass minicom age whois yq iputils-ping p7zip \
    xorriso parted dosfstools mtools

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

# SOPS configuration
ENV SOPS_AGE_KEY_FILE=keys/primary.key

# Taskfile experiments
ENV TASK_X_MAP_VARIABLES=2
ENV TASK_X_ENV_PRECEDENCE=1

# Ansible vars
# This is needed for WSL-backed Docker because the file is world-writable
ENV ANSIBLE_CONFIG=./ansible.cfg

# Autocomplete
RUN \
    talosctl completion bash | sudo tee /etc/bash_completion.d/talosctl.bash > /dev/null && \
    talhelper completion bash | sudo tee /etc/bash_completion.d/talhelper.bash > /dev/null && \
    helmfile completion bash | sudo tee /etc/bash_completion.d/helmfile.bash > /dev/null
