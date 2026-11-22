#!/bin/sh
# End-to-end test of ci-tools on a real dind: runs the fixture project
# (tests/fixture) through lib/tekton-step.sh, the shared Pipelines' step, as
# a push, a docs-only pull request, a failing pull request and a dry-run
# release. Runs in the docker Task's step in infra-mk3's CI
# (.tekton/ci-tools/), from the ci-tools directory, with the image to test
# already built:
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
git_ci() { git -c user.email=ci@ci -c user.name=ci "$@"; }

# A fresh workspace whose origin repository has the fixture on master. A
# pull request scenario commits to a branch on top (change), then builds
# it.
setup() {
	w="$1"
	rm -rf "$w"
	mkdir -p "$w/origin"
	cp -R "$here/tests/fixture/." "$w/origin/"
	cp "$here/flake.lock" "$w/origin/flake.lock"
	(
		cd "$w/origin"
		git init -q -b master .
		git_ci add -A
		git_ci commit -qm fixture
	)
}
change() { (cd "$w/origin" && git checkout -q -B pr master && eval "$1" && git_ci add -A && git_ci commit -qm change && git checkout -q master); }
step() {
	event="$1"
	revision="$2"
	shift 2
	env WS="$w" CI_TOOLS_IMAGE="$image" REPO_URL="$w/origin" REVISION="$revision" \
		CI_CPUS="${CI_CPUS:-4}" DOCKER_TASK_OUTPUT="$w/output" "$@" \
		sh "$here/lib/tekton-step.sh" "$event"
}
head_of() { git -C "$w/origin" rev-parse "$1"; }

# The stages result is compact JSON on one line (lib/stages-report.py).
stages_of() { grep -o '"name": *"[^"]*"' "$w/output" | cut -d'"' -f4 | tr '\n' ' ' | sed 's/ $//'; }

echo "=== push: every stage"
setup "$ws/e2e-push"
step push "$(head_of master)" || fail "push run failed"
got=$(stages_of)
[ "$got" = "lint unit docs cleanup" ] || fail "push ran '$got', want 'lint unit docs cleanup'"
grep -q '"result": *"failed"' "$w/output" && fail "a push stage failed"
[ "$(wc -l <"$w/with-runs")" -eq 1 ] || fail "the with job lint and unit share ran $(wc -l <"$w/with-runs") times, want once"

echo "=== pull request: a docs-only change runs only docs and the test guard"
setup "$ws/e2e-pr"
change 'echo "More words." >>README.md'
step pull_request "$(head_of pr)" CI_PR_LABELS=test-removal-approved || fail "pull request run failed"
got=$(stages_of)
[ "$got" = "docs test-guard" ] || fail "docs-only pull request ran '$got', want 'docs test-guard'"
grep -q '"result": *"failed"' "$w/output" && fail "a pull request stage failed"

echo "=== pull request: a failing stage is in the result for the report"
setup "$ws/e2e-fail"
change "printf 'package main\n\nfunc  bad() {}\n' >cmd/fixture/bad.go"
step pull_request "$(head_of pr)" || fail "the step failed instead of leaving the result"
grep -q '"name": *"lint", *"result": *"failed"' "$w/output" || fail "the failed lint stage is not in the result: $(cat "$w/output")"

echo "=== release: a dry run builds the assets and prints the publishing"
setup "$ws/e2e-release"
out=$(step release "$(head_of master)" RELEASE_REF=refs/tags/v0.1.0 CI_RELEASE_DRY_RUN=true) || fail "dry-run release failed: $out"
echo "$out"
for f in crds.yaml fixture-linux-amd64 checksums.txt; do
	[ -s "$w/ci/release-assets/$f" ] || fail "release asset $f missing"
done
(cd "$w/ci/release-assets" && sha256sum -c checksums.txt >/dev/null) || fail "checksums.txt does not match"
echo "$out" | grep -qF "would run: helm push $w/ci/charts/fixture-0.1.0.tgz oci://ghcr.io/example/charts" || fail "no chart push"
echo "$out" | grep -qF "would run: python3 -I /ci-tools/lib/upload-release-assets.py v0.1.0" || fail "no release upload"

echo "e2e: all passed"
