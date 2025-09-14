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
    END_OCTET="$((START_OCTET + COUNT - 1 + OFFSET))"
    for OCTET in $(seq "${START_OCTET}" "${END_OCTET}"); do
        echo "${BASE_ADDRESS}.${OCTET}"
    done
}
