#!/usr/bin/env bash

set -euo pipefail

# Give an address e.g. A.B.C.D and a count N, generate addresses A.B.C.(D) through A.B.C.(D+N-1)
# Optionally, an offset can be provided to add to the starting octet.
generate_addresses() {
    FIRST_ADDRESS="${1}"
    COUNT="${2}"
    OFFSET="${3:-0}"

    BASE_ADDRESS="${FIRST_ADDRESS%.*}"
    START_OCTET="$((${FIRST_ADDRESS##*.} + OFFSET))"
    END_OCTET="$((START_OCTET + COUNT - 1))"

    ADDRESSES=()
    for OCTET in $(seq "${START_OCTET}" "${END_OCTET}"); do
        ADDRESSES+=("${BASE_ADDRESS}.${OCTET}")
    done

    echo "${ADDRESSES[*]}"
}

# Indent text by a number of tabs (4 spaces each)
indent() {
    TABS="${1}"
    shift
    TEXT="${*}"

    printf "%$(( 4 * TABS ))s%s\n" "" "${TEXT}"
}

# Given an IP address within a subnet, return the network address of that subnet.
get_network_address() {
    IP_ADDRESS="${1}"
    CIDR_BITS="${2}"

    IFS=. read -ra octets <<< "${IP_ADDRESS}"
    NETWORK_ADDRESS_OCTETS=()
    REMAINING_BITS="${CIDR_BITS}"
    
    for i in {0..3}; do
        if [ "${REMAINING_BITS}" -le 0 ]; then
            NETWORK_ADDRESS_OCTETS+=("0")
            continue
        fi

        BITS_IN_OCTET=$(( REMAINING_BITS < 8 ? REMAINING_BITS : 8 ))
        MASK=$(( 256 - 2**(8 - BITS_IN_OCTET) ))
        NETWORK_ADDRESS_OCTETS+=("$(( octets[i] & MASK ))")
        REMAINING_BITS=$(( REMAINING_BITS - 8 ))
    done

    (IFS=.; printf "%s" "${NETWORK_ADDRESS_OCTETS[*]}")
}
