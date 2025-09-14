#!/bin/ash

# shellcheck shell=dash

# Set vars based on the pod index. This is used to ensure that each pod connects to a different VPN endpoint.

export POD_INDEX="${POD_NAME##*-}"

echo "Setting pod-specific variables for ${POD_NAME}:"
# shellcheck disable=SC2153 # POD_SPECIFIC_VARS is set in the manifest
for POD_SPECIFIC_VAR in ${POD_SPECIFIC_VARS}; do
    # Example: WIREGUARD_ADDRESSES="${WIREGUARD_ADDRESSES_0}"
    eval "export \"${POD_SPECIFIC_VAR}=\$${POD_SPECIFIC_VAR}_${POD_INDEX}\""
    echo "${POD_SPECIFIC_VAR}=$(eval echo "\$${POD_SPECIFIC_VAR}")"
done
