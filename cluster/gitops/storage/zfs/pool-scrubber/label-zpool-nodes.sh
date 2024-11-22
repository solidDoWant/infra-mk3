#!/bin/bash

# Labels local storage zpool nodes so that the scrub deamonset will deploy to them

set -euo pipefail

for NODE_NAME in $(kubectl get nodes -o name -l 'zfs.home.arpa/node.local-storage-deployed=true'); do
    echo "Labeling ${NODE_NAME}"
    kubectl label --overwrite "${NODE_NAME}" 'zfs.home.arpa/node.local-storage-scrub=true'
done
