#!/bin/sh
# Tests lib/stale-images.sh: an old version of an image the tree names
# is selected, and the current version and unrelated images are not.
set -eu
cd "$(dirname "$0")/../lib"
keep=$(mktemp)
trap 'rm -f "$keep"' EXIT
cat >"$keep" <<'LIST'
mirror.gcr.io/kindest/node:v1.37.0@sha256:aaaa
quay.io/example/fake:v2.15.0
quay.io/jetstack/cert-manager-controller:v1.20.0@sha256:bbbb
LIST
got=$(printf '%s\n' \
	mirror.gcr.io/kindest/node:v1.37.0 \
	mirror.gcr.io/kindest/node:v1.36.0 \
	quay.io/example/fake:v2.15.0 \
	quay.io/example/fake:v2.14.0 \
	quay.io/jetstack/cert-manager-controller:v1.19.0 \
	quay.io/jetstack/cert-manager-controller:'<none>' \
	myproject-ci:abc \
	ghcr.io/example/myproject:e2e |
	/bin/sh ./stale-images.sh "$keep")
want='mirror.gcr.io/kindest/node:v1.36.0
quay.io/example/fake:v2.14.0
quay.io/jetstack/cert-manager-controller:v1.19.0'
[ "$got" = "$want" ] || { printf 'stale-images.sh printed:\n%s\nwant:\n%s\n' "$got" "$want" >&2; exit 1; }
echo "stale-images_test.sh: ok"
