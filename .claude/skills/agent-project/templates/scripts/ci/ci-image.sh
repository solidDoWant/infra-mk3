#!/bin/sh
# Builds the CI image (scripts/ci/ci-image.Dockerfile) and prints its tag. The
# build context holds only what the dev shell depends on, so the layer cache
# hits unless flake.nix, flake.lock or the Go version changed.
#
#   image=$(scripts/ci/ci-image.sh)
set -eu
cd "$(dirname "$0")/../.."
context=$(mktemp -d)
trap 'rm -rf "$context"' EXIT
cp flake.nix flake.lock "$context/"
# The flake reads go.mod only for the Go version (TEMPLATE: drop for non-Go
# projects, or copy what else the dev shell reads).
grep -E '^(module|go|toolchain) ' go.mod > "$context/go.mod"
tag={{PROJECT}}-ci:$(cat "$context/flake.nix" "$context/flake.lock" "$context/go.mod" | sha256sum | cut -c1-16)
docker build -q -f scripts/ci/ci-image.Dockerfile -t "$tag" "$context" >&2
echo "$tag"
