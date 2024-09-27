FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Generally helpful tools
RUN apt update && apt install --no-install-recommends -y \
    file sshpass minicom age whois yq iputils-ping

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

# SOPS configuration
ENV SOPS_AGE_KEY_FILE=keys/primary.key

# Taskfile experiments
ENV TASK_X_MAP_VARIABLES=2
ENV TASK_X_ENV_PRECEDENCE=1

# Ansible vars
# This is needed for WSL-backed Docker because the file is world-writable
ENV ANSIBLE_CONFIG=./ansible.cfg
