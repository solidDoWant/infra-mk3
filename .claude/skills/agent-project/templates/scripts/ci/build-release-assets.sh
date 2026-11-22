#!/usr/bin/env bash
# Builds the files attached to a GitHub release, in the directory given:
#   crds.yaml                                   every CRD of the chart, one multi-document file;
#   {{PROJECT}}-client-<os>-<arch>               static client for linux and darwin, amd64 and arm64;
#   checksums.txt                               SHA-256 sums of the client binaries and crds.yaml.
#
#   scripts/ci/build-release-assets.sh <version> <output-dir>
#
# crds.yaml is the concatenation of config/crd/bases, the source of the chart's
# templates/crds (scripts/ci/release-assets_test.sh checks that they match).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

version="${1:?usage: build-release-assets.sh <version> <output-dir>}"
version="${version#v}"
out="${2:?usage: build-release-assets.sh <version> <output-dir>}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]]; then
	echo "build-release-assets: '$version' is not a release version" >&2
	exit 1
fi

mkdir -p "$out"
cat config/crd/bases/*.yaml >"$out/crds.yaml"

for target in linux/amd64 linux/arm64 darwin/amd64 darwin/arm64; do
	os="${target%/*}"
	arch="${target#*/}"
	CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" go build -trimpath \
		-ldflags="-s -w -X main.version=$version" \
		-o "$out/{{PROJECT}}-client-$os-$arch" ./cmd/{{PROJECT}}-client
done

(cd "$out" && sha256sum crds.yaml {{PROJECT}}-client-* >checksums.txt)
echo "build-release-assets: wrote the assets to $out"
