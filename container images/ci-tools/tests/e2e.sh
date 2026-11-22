#!/bin/sh
# End-to-end test of ci-tools on a real dind: runs the fixture project
# (tests/fixture) through ci-stages, as a push and as a docs-only pull
# request, and through a dry-run ci-release, the way the shared Pipelines do.
# Runs in the docker Task's step in infra-mk3's CI (.tekton/ci-tools/), from
# the ci-tools directory, with the image to test already built:
#
#   tests/e2e.sh <ci-tools image> <workspace dir>
#
# CI_REPO must be a repository the run's ServiceAccount may read through
# githubgate (the stage TLS check and the release's TLS check call it).
set -eu
image="${1:?usage: e2e.sh <ci-tools image> <workspace dir>}"
ws="${2:?usage: e2e.sh <ci-tools image> <workspace dir>}"
: "${CI_REPO:?CI_REPO must name a readable repository}"
here=$(pwd)
fail() { echo "e2e: $*" >&2; exit 1; }

# The pod files the shared Pipelines' step copies for ci-tools.
pod_files() {
	pod="$1/ci/pod"
	mkdir -p "$pod"
	cp /etc/ssl/certs/ca-certificates.crt "$pod/system-ca.crt" 2>/dev/null || true
	if [ -r /var/run/githubgate/trust/ca.crt ]; then
		mkdir -p "$pod/trust"
		cp /var/run/githubgate/trust/ca.crt "$pod/trust/"
	fi
	if [ -n "${SSL_CERT_FILE:-}" ] && [ -r "$SSL_CERT_FILE" ]; then cp "$SSL_CERT_FILE" "$pod/ssl-cert-file"; fi
	if [ -x /opt/registrygate/docker-credential-registrygate ]; then
		cp /opt/registrygate/docker-credential-registrygate "$pod/"
		cp /var/run/secrets/registrygate/token "$pod/token"
	fi
	if [ -f "${HOME:-/nonexistent}/.docker/config.json" ]; then cp "$HOME/.docker/config.json" "$pod/docker-config.json"; fi
}

# A fresh workspace with the fixture as a git checkout: master, and a branch
# on top for the pull request.
setup() {
	w="$1"
	rm -rf "$w"
	mkdir -p "$w/src"
	cp -R "$here/tests/fixture/." "$w/src/"
	cp "$here/flake.lock" "$w/src/flake.lock"
	(
		cd "$w/src"
		git init -q -b master .
		git -c user.email=ci@ci -c user.name=ci add -A
		git -c user.email=ci@ci -c user.name=ci commit -qm fixture
		git update-ref refs/remotes/origin/master HEAD
	)
	pod_files "$w"
}

ci_tools() {
	w="$1"
	shift
	docker run --rm --network host -v "$w:$w" -w "$w/src" \
		-v /run/ci-kind:/run/ci-kind:ro -v /opt/ci-kind:/opt/ci-kind:ro \
		-v /etc/docker/certs.d:/etc/docker/certs.d:ro \
		-e WS="$w" -e CI_REPO="$CI_REPO" -e CI_HOST="$(hostname)" -e CI_CPUS="${CI_CPUS:-4}" \
		-e DOCKER_HOST="${DOCKER_HOST:-tcp://127.0.0.1:2375}" -e REGISTRYGATE_HOSTS="${REGISTRYGATE_HOSTS:-}" \
		"$@"
}

# stages.json is compact JSON on one line (lib/stages-report.py).
stages_of() { grep -o '"name": *"[^"]*"' "$1/ci/stages.json" | cut -d'"' -f4 | tr '\n' ' ' | sed 's/ $//'; }

echo "=== push: every stage"
w="$ws/e2e-push"
setup "$w"
ci_tools "$w" "$image" ci-stages push || fail "push run failed"
got=$(stages_of "$w")
[ "$got" = "lint unit docs cleanup" ] || fail "push ran '$got', want 'lint unit docs cleanup'"
grep -q '"result": *"failed"' "$w/ci/stages.json" && fail "a push stage failed"

echo "=== pull request: a docs-only change runs only docs"
w="$ws/e2e-pr"
setup "$w"
(cd "$w/src" && echo "More words." >>README.md && git -c user.email=ci@ci -c user.name=ci commit -qam docs)
ci_tools "$w" "$image" ci-stages pull_request || fail "pull request run failed"
got=$(stages_of "$w")
[ "$got" = "docs" ] || fail "docs-only pull request ran '$got', want 'docs'"

echo "=== pull request: a failing stage fails the run and is reported"
w="$ws/e2e-fail"
setup "$w"
(cd "$w/src" && printf 'package main\n\nfunc  bad() {}\n' >cmd/fixture/bad.go && git -c user.email=ci@ci -c user.name=ci add -A && git -c user.email=ci@ci -c user.name=ci commit -qm bad)
if ci_tools "$w" "$image" ci-stages pull_request; then fail "a failing lint stage did not fail the run"; fi
grep -q '"name": *"lint"' "$w/ci/stages.json" || fail "the failed run left no stages result"

echo "=== release: a dry run builds the assets and prints the publishing"
w="$ws/e2e-release"
setup "$w"
out=$(ci_tools "$w" -e CI_RELEASE_DRY_RUN=true "$image" ci-release 0.1.0) || fail "dry-run release failed: $out"
echo "$out"
for f in crds.yaml fixture-linux-amd64 checksums.txt; do
	[ -s "$w/ci/release-assets/$f" ] || fail "release asset $f missing"
done
(cd "$w/ci/release-assets" && sha256sum -c checksums.txt >/dev/null) || fail "checksums.txt does not match"
echo "$out" | grep -qF "would run: helm push $w/ci/charts/fixture-0.1.0.tgz oci://ghcr.io/example/charts" || fail "no chart push"
echo "$out" | grep -qF "would run: python3 -I /ci-tools/lib/upload-release-assets.py v0.1.0" || fail "no release upload"

echo "e2e: all passed"
