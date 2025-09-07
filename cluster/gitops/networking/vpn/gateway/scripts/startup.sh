#!/bin/ash

# shellcheck shell=dash
set -eu

# shellcheck source=/dev/null
. "$(dirname "${0}")/set-env-vars.sh"
exec /gluetun-entrypoint "$@"
