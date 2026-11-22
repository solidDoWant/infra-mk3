#!/usr/bin/env bash
# Tests of scripts/ci/publish-release.sh, in its dry run: what it publishes for
# a final version and a pre-release, and that it refuses other versions.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail() { echo "publish-release_test: $*" >&2; exit 1; }

out=$(PUBLISH_DRY_RUN=true ./scripts/ci/publish-release.sh v1.2.3 2>&1) || fail "final version failed: $out"
grep -qF "would run: make build-images VERSION=1.2.3 PUSH_ALL=true" <<<"$out" || fail "no image push: $out"
grep -qF "would run: crane tag ghcr.io/{{GH_USER_LOWER}}/{{PROJECT}}:1.2.3 latest" <<<"$out" || fail "server image not tagged latest: $out"
grep -qF "would run: crane tag ghcr.io/{{GH_USER_LOWER}}/{{PROJECT}}-client:1.2.3 latest" <<<"$out" ||
	fail "client image not tagged latest: $out"
grep -qF "would run: helm package deploy/charts/{{PROJECT}} --version 1.2.3 --app-version 1.2.3" <<<"$out" ||
	fail "no chart package: $out"
grep -qF "would run: helm push build/chart/{{PROJECT}}-1.2.3.tgz oci://ghcr.io/{{GH_USER_LOWER}}/charts" <<<"$out" ||
	fail "no chart push: $out"
grep -qF "would run: ./scripts/ci/build-release-assets.sh 1.2.3 build/release-assets" <<<"$out" || fail "no release assets build: $out"
[[ "$(grep -n 'build-release-assets' <<<"$out" | cut -d: -f1)" -lt "$(grep -n 'make build-images' <<<"$out" | cut -d: -f1)" ]] ||
	fail "assets built after the images were pushed: $out"
grep -qF "would run: ./scripts/ci/upload-release-assets.py v1.2.3 build/release-assets" <<<"$out" || fail "no release upload: $out"
[[ "$(grep -n 'upload-release-assets' <<<"$out" | cut -d: -f1)" -gt "$(grep -n 'helm push' <<<"$out" | cut -d: -f1)" ]] ||
	fail "release created before the chart was pushed: $out"
# The chart is pushed after the images and latest.
[[ "$(grep -n 'helm push' <<<"$out" | cut -d: -f1)" -gt "$(grep -n 'crane tag' <<<"$out" | tail -n1 | cut -d: -f1)" ]] ||
	fail "chart pushed before latest moved: $out"

out=$(PUBLISH_DRY_RUN=true ./scripts/ci/publish-release.sh 1.2.3-rc.1 2>&1) || fail "pre-release failed: $out"
grep -qF "would run: make build-images VERSION=1.2.3-rc.1 PUSH_ALL=true" <<<"$out" || fail "no pre-release image push: $out"
grep -qF "would run: helm push build/chart/{{PROJECT}}-1.2.3-rc.1.tgz" <<<"$out" || fail "no pre-release chart push: $out"
grep -q "latest" <<<"$out" && fail "a pre-release moved latest: $out"

for bad in 1.2 1.2.3-beta.1 1.2.3-rc.1-x "1.2.3; true" ""; do
	if PUBLISH_DRY_RUN=true ./scripts/ci/publish-release.sh "$bad" >/dev/null 2>&1; then
		fail "version '$bad' was accepted"
	fi
done
echo "publish-release_test: passed"
