#!/bin/bash

# Labels local storage zpool nodes so that the scrub deamonset will deploy to them

set -euo pipefail

install_kubectl() {
    echo "Installing kubectl..."
    apt update
    apt install --no-install-recommends -y curl ca-certificates
    KERNEL="$(uname -s | tr '[:upper:]' '[:lower:]')"
    PRETTY_ARCH="$(case "$(uname -m)" in 'x86_64') echo "amd64";; *) uname -m;; esac)"
    VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
    curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${VERSION}/bin/${KERNEL}/${PRETTY_ARCH}/kubectl"
    chmod +x /usr/local/bin/kubectl
    echo "Installed kubectl ${VERSION}"
}

check_env_vars
install_kubectl

for NODE_NAME in $(kubectl get nodes -o name -l 'zfs.home.arpa/node.local-storage-deployed=true'); do
    echo "Labeling ${NODE_NAME}"
    kubectl label --overwrite "${NODE_NAME}" 'zfs.home.arpa/node.local-storage-scrub=true'
done
