#!/usr/bin/env bash
# Publishes the images and the chart of a release: the release stage of the
# Tekton release run (scripts/ci/stages.sh release). Runs in the CI image,
# where docker, crane and helm reach ghcr.io through registrygate, which
# pushes only for the release ServiceAccount (ci-release). It never holds a
# GitHub token; the release-manager agent creates the GitHub release after
# this run passes.
#
#   scripts/ci/publish-release.sh <version>|v<version>
#
# TEMPLATE: list the project's images and charts. Each step must be safe to
# run again for the same version: a failed release is re-run by pushing its
# tag again.
# PUBLISH_DRY_RUN=true prints the commands instead of running them (tests).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

version="${1:?usage: publish-release.sh <version>}"
version="${version#v}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]]; then
	echo "publish-release: '$version' is not a release version (X.Y.Z or X.Y.Z-rc.K)" >&2
	exit 1
fi

run() {
	if [[ "${PUBLISH_DRY_RUN:-false}" == "true" ]]; then
		echo "would run: $*"
	else
		"$@"
	fi
}

images=(ghcr.io/{{GH_USER_LOWER}}/{{PROJECT}})

run make build-images VERSION="$version" PUSH_ALL=true
# Only a final version (no -rc.K) moves latest.
if [[ "$version" != *-* ]]; then
	for image in "${images[@]}"; do
		run crane tag "$image:$version" latest
	done
fi
if [[ -d deploy/charts/{{PROJECT}} ]]; then
	run helm package deploy/charts/{{PROJECT}} --version "$version" --app-version "$version" --destination build/chart
	run helm push "build/chart/{{PROJECT}}-$version.tgz" oci://ghcr.io/{{GH_USER_LOWER}}/charts
fi
echo "publish-release: published $version"
