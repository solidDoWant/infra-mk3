#!/bin/sh
# The shared Pipelines' ci and publish step, in the docker Task's step (an
# Alpine image with git and the Docker CLI): checks the commit out, copies the
# pod's files that dockerd can't see, and runs ci-tools on the run's dockerd.
# The Pipelines take it from the image they pin, so it changes with ci-tools:
#
#   docker run --rm "$CI_TOOLS_IMAGE" cat /ci-tools/lib/tekton-step.sh >/tmp/step.sh
#   sh /tmp/step.sh pull_request|push|release
#
# Environment:
#   CI_TOOLS_IMAGE  the ci-tools image (by digest)
#   REPO_URL        the repository to clone
#   REVISION        the commit to build
#   CI_REPO         owner/name
#   CI_CPUS         the dind sidecar's CPU request, default 8
#   CI_PR_LABELS    pull_request: the labels, for the test guard
#   RELEASE_REF     release: refs/tags/v<version>
#   WS              the workspace, default /workspace/source
#   CI_RELEASE_DRY_RUN  passed on (tests)
#
# pull_request and push write the stages result to $DOCKER_TASK_OUTPUT for the
# report task, and exit 0 once it exists: the report fails the run when a
# stage failed (a finally task can't read a failed task's results).
set -eu
event="${1:?usage: tekton-step.sh pull_request|push|release}"
: "${CI_TOOLS_IMAGE:?}" "${REPO_URL:?}" "${REVISION:?}" "${CI_REPO:?}"
WS="${WS:-/workspace/source}"
src="$WS/src"
git_ci() { git -c user.email=ci@ci -c user.name=ci "$@"; }

case "$event" in
pull_request | push) ;;
release)
	ref="${RELEASE_REF:?release needs RELEASE_REF}"
	version="${ref#refs/tags/v}"
	[ "$version" != "$ref" ] || { echo "tekton-step: $ref is not a version tag" >&2; exit 1; }
	;;
*) echo "tekton-step: unknown event '$event'" >&2; exit 2 ;;
esac

rm -rf "$src"
mkdir -p "$src"
cd "$src"
git init -q .
git remote add origin "$REPO_URL"
if [ "$event" = release ]; then
	git fetch -q --depth 1 origin "$REVISION"
else
	# The full history: the stage selection needs the merge base with master.
	git fetch -q origin '+refs/heads/master:refs/remotes/origin/master' "$REVISION"
fi
git checkout -q --detach "$REVISION"
if [ "$event" = pull_request ]; then
	# Test the pull request merged with master, as actions/checkout does.
	if ! git_ci merge -q --no-ff --no-edit origin/master; then
		echo "the pull request conflicts with master; rebase it:" >&2
		git diff --name-only --diff-filter=U >&2
		exit 1
	fi
fi

# The pod's files ci-tools needs; dockerd sees only the workspace.
pod="$WS/ci/pod"
rm -rf "$pod"
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

ci_tools() {
	docker run --rm --network host -v "$WS:$WS" -w "$src" \
		-v /run/ci-kind:/run/ci-kind:ro -v /opt/ci-kind:/opt/ci-kind:ro \
		-v /etc/docker/certs.d:/etc/docker/certs.d:ro \
		-e WS="$WS" -e CI_REPO="$CI_REPO" -e CI_HOST="$(hostname)" -e CI_CPUS="${CI_CPUS:-8}" \
		-e DOCKER_HOST="${DOCKER_HOST:-tcp://127.0.0.1:2375}" -e REGISTRYGATE_HOSTS="${REGISTRYGATE_HOSTS:-}" \
		-e CI_PR_LABELS="${CI_PR_LABELS:-}" -e CI_RELEASE_DRY_RUN="${CI_RELEASE_DRY_RUN:-}" \
		"$CI_TOOLS_IMAGE" "$@"
}

if [ "$event" = release ]; then
	ci_tools ci-release "$version"
	exit
fi

status=0
ci_tools ci-stages "$event" || status=$?
result="$WS/ci/stages.json"
if [ ! -s "$result" ]; then
	echo "tekton-step: ci-stages left no stages result (exit $status)" >&2
	exit "$((status == 0 ? 1 : status))"
fi
if [ -n "${DOCKER_TASK_OUTPUT:-}" ]; then cp "$result" "$DOCKER_TASK_OUTPUT"; fi
[ "$status" -eq 0 ] && exit 0
# Tekton drops a result that its termination message can't hold, and then
# skips the report task, so the run would pass. stages-report.py keeps the
# result under 1536 bytes; past 1800 (escapes included) fail here instead.
size=$(sed 's/["\\]/&&/g' "$result" | wc -c)
if [ "$size" -gt 1800 ]; then
	echo "tekton-step: stages failed and their result ($size bytes) is too big to report" >&2
	exit "$status"
fi
echo "tekton-step: stages failed; the report task fails the run"
exit 0
