#!/usr/bin/env bash
# Prints the pinned images the e2e cluster's pods pull, one per line, derived
# from the files that name them (run from the repository root): the image
# references quoted in the e2e Go sources and install-cert-manager.sh. test/e2e/up.sh preloads them through
# the Docker daemon, and scripts/ci/cleanup.sh keeps them while it removes
# older versions. With --node it prints the kind node image too.
set -euo pipefail
{
	if [ "${1:-}" = --node ]; then
		grep -oE '^node_image="[^"]+"' test/e2e/up.sh | cut -d'"' -f2
	fi
	mapfile -t sources < <(git ls-files --cached --others --exclude-standard -- 'test/e2e/*.go' test/e2e/install-cert-manager.sh)
	if ((${#sources[@]} > 0)); then
		grep -ohE '"(ghcr\.io|quay\.io|mirror\.gcr\.io)/[^"]+@sha256:[0-9a-f]{64}"' "${sources[@]}" | tr -d '"' || true
	fi
} | sort -u
