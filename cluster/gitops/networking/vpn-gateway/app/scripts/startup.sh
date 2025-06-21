#!/bin/ash

# shellcheck shell=dash
set -eu

# Set vars based on the pod index. This is used to ensure that each pod connects to a different VPN endpoint.
# If they connected to the same endpoint then the endpoint would (statelessly) send packets to each of the pods randomly.

echo "Setting pod-specific variables for ${POD_NAME}:"
for POD_SPECIFIC_VAR in ${POD_SPECIFIC_VARS}; do
    # Example: WIREGUARD_ADDRESSES="${WIREGUARD_ADDRESSES_0}"
    eval "export \"${POD_SPECIFIC_VAR}=\$${POD_SPECIFIC_VAR}_${POD_NAME##*-}\""
    echo "${POD_SPECIFIC_VAR}=$(eval echo "\$${POD_SPECIFIC_VAR}")"
done

echo
echo "Starting gluetun..."
exec /gluetun-entrypoint "$@"
