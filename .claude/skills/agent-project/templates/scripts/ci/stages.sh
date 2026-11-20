#!/bin/sh
# Runs the CI stages on Tekton, all at the same time, each in its own
# container of the CI image (scripts/ci/ci-image.sh), inside the docker Task's
# dind. Runs in the docker Task's step, from the checkout at $WS/src, where WS
# is the Task's workspace: the step and dockerd see it at the same path.
#
#   scripts/ci/stages.sh pull_request|push
#   RELEASE_VERSION=<version> scripts/ci/stages.sh release
#
# A pull request runs the stages its changes need (scripts/ci/changes.py); a
# push runs them all and then cleans the Docker storage the cache promoter
# keeps. A release runs one stage, release (scripts/ci/publish-release.sh).
# Prints a table of every stage's result, time, memory and CPU, and the VM's
# peak memory, then exits non-zero when a stage failed.
#
# TEMPLATE: adapt command_of (the stages) and changes.py (which changes need
# which stages) to the project's Makefile. The Go cache volumes are for Go
# projects; drop or replace them for other languages.
set -eu

event="${1:?usage: stages.sh pull_request|push|release}"
t0=$(date +%s)
elapsed() { echo $(($(date +%s) - t0)); }

src=$(git rev-parse --show-toplevel)
cd "$src"
WS=$(dirname "$src")
ci="$WS/ci"
out="$ci/stages"
mkdir -p "$ci/bin" "$ci/docker" "$out"

# Samples the VM's used memory (total minus available, so page cache does not
# count) every 2 seconds and keeps the peak in KiB, to size the dind sidecar.
# One read of /proc/meminfo per sample keeps it light for the small step.
peak_file="$ci/vm-peak-kib"
echo 0 >"$peak_file"
(
	peak=0
	while :; do
		used=$(awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } END { print t - a }' /proc/meminfo)
		if [ "$used" -gt "$peak" ]; then
			peak=$used
			echo "$peak" >"$peak_file"
		fi
		sleep 2
	done
) &
sampler=$!
trap 'kill "$sampler" 2>/dev/null || true' EXIT

image=$(./scripts/ci/ci-image.sh)
echo "ci image $image ready after $(elapsed)s"

# Runs a command in the CI image's dev shell, from the checkout.
in_image() {
	docker run --rm -i -v "$WS:$WS" -w "$src" "$image" bash -c \
		'source /etc/devshell.sh && git config --global --add safe.directory "*" && "$@"' bash "$@"
}

if [ "$event" = release ]; then
	stages=release
elif [ "$event" = push ]; then
	stages=$(in_image ./scripts/ci/changes.py push </dev/null)
else
	# Both the old and the new path of a moved file.
	git diff --no-renames --name-only "$(git merge-base HEAD origin/master)" HEAD >"$ci/changed-files"
	stages=$(in_image ./scripts/ci/changes.py pull_request <"$ci/changed-files")
fi
if [ -z "$stages" ]; then
	echo "no stage needs to run for these changes"
	exit 0
fi
echo "stages: $stages"

# What a stage needs to reach the registries through registrygate like this
# step's own Docker CLI: the system CAs plus registrygate's CA (dockerd's
# certs.d, the same CA for every intercepted host), the credential helper, its
# token and the Docker configuration that names it.
cp /etc/ssl/certs/ca-certificates.crt "$ci/ca-bundle.crt"
docker run --rm -v /etc/docker/certs.d:/certsd:ro --entrypoint /bin/sh "$image" \
	-c 'f=$(ls /certsd/*/ca.crt 2>/dev/null | head -n1); if [ -n "$f" ]; then cat "$f"; fi' >>"$ci/ca-bundle.crt"
if [ -x /opt/registrygate/docker-credential-registrygate ]; then
	cp /opt/registrygate/docker-credential-registrygate "$ci/bin/"
	cp /var/run/secrets/registrygate/token "$ci/token"
fi
if [ -f "${HOME:-/nonexistent}/.docker/config.json" ]; then
	cp "$HOME/.docker/config.json" "$ci/docker/config.json"
fi

# The Go caches live on dockerd's volume, which the cache promoter keeps after
# a successful master push run.
docker volume create gomod >/dev/null
docker volume create gobuild >/dev/null

command_of() {
	case "$1" in
	lint) echo 'make lint' ;;
	unit) echo 'make test && make build' ;;
	generate) echo 'make check-generate' ;;
	integration) echo 'make test-integration' ;;
	e2e) echo 'make test-e2e' ;;
	# Fuzzing, if the project has fuzz targets: its own stage, targets at the
	# same time with bounded -parallel (fixed-time work never goes serially into
	# unit, and unbounded workers starve the stages sharing this VM).
	# fuzz) echo 'make test-fuzz' ;;
	docs) echo 'make docs-check' ;;
	release)
		# The version comes in through the environment, never the command
		# text, and the stage container expands it.
		# shellcheck disable=SC2016
		echo './scripts/ci/publish-release.sh "$RELEASE_VERSION"'
		;;
	esac
}

start_stage() {
	stage="$1"
	mount="-v $WS:$WS"
	# OPTIONAL (projects that run kind): create clusters with
	#   /run/ci-kind/bin/ci-kind-config --name "$KIND_CLUSTER" --image <node image> kind.yaml | kind create cluster --config=-
	# so kind nodes pull through registrygate and keep their images between
	# runs (infra-mk3: cluster/gitops/ci/tekton/docker/task/task.yaml).
	case "$stage" in
	e2e*) [ -x /run/ci-kind/bin/ci-kind-config ] && mount="$mount -v /run/ci-kind:/run/ci-kind:ro -v /opt/ci-kind:/opt/ci-kind:ro" ;;
	esac
	date +%s >"$out/$stage.start"
	(
		status=0
		# shellcheck disable=SC2086 # $mount is a list of options
		docker run --rm --name "stage-$stage" --network host $mount -w "$src" \
			-v gomod:/cache/gomod -v gobuild:/cache/gobuild \
			-e GOMODCACHE=/cache/gomod -e GOCACHE=/cache/gobuild/go \
			-e GOLANGCI_LINT_CACHE=/cache/gobuild/golangci-lint \
			-e DOCKER_HOST=tcp://127.0.0.1:2375 -e DOCKER_CONFIG="$ci/docker" \
			-e REGISTRYGATE_HOSTS="${REGISTRYGATE_HOSTS:-}" -e REGISTRYGATE_TOKEN_FILE="$ci/token" \
			-e TESTCONTAINERS_RYUK_DISABLED=true \
			-e CI_BIN="$ci/bin" -e CI_CA="$ci/ca-bundle.crt" -e CI_STATS="$out/$stage.stats" \
			-e KIND_CLUSTER="{{PROJECT}}-ci-$stage" \
			-e RELEASE_VERSION="${RELEASE_VERSION:-}" \
			-e STAGE_COMMAND="$(command_of "$stage")" \
			"$image" bash -c '
				source /etc/devshell.sh
				export PATH="$CI_BIN:$PATH" SSL_CERT_FILE="$CI_CA"
				git config --global --add safe.directory "*"
				status=0
				bash -c "set -e; $STAGE_COMMAND" || status=$?
				# This container cgroup: the stage alone.
				{
					echo "memory_peak $(cat /sys/fs/cgroup/memory.peak 2>/dev/null || echo 0)"
					grep usage_usec /sys/fs/cgroup/cpu.stat 2>/dev/null || echo "usage_usec 0"
				} >"$CI_STATS"
				exit "$status"
			' >"$out/$stage.log" 2>&1 || status=$?
		date +%s >"$out/$stage.end"
		echo "$status" >"$out/$stage.exit"
	) &
}

for stage in $stages; do
	start_stage "$stage"
done
echo "started after $(elapsed)s: $stages"

# Prints each passed stage's log as one block as soon as it ends, and the
# failed ones last, so the failure is at the end of the step log.
failed=""
remaining="$stages"
while [ -n "$remaining" ]; do
	next=""
	for stage in $remaining; do
		if [ ! -f "$out/$stage.exit" ]; then
			next="$next $stage"
			continue
		fi
		took=$(($(cat "$out/$stage.end") - $(cat "$out/$stage.start")))
		if [ "$(cat "$out/$stage.exit")" = 0 ]; then
			echo "==================== stage $stage: passed in ${took}s ===================="
			cat "$out/$stage.log"
		else
			echo "stage $stage: FAILED after ${took}s (log below, after the other stages)"
			failed="$failed $stage"
		fi
	done
	remaining=$(echo "$next" | xargs)
	if [ -n "$remaining" ]; then sleep 2; fi
done
# Every stage has ended: stop the sampler, or the wait below never returns.
kill "$sampler" 2>/dev/null || true
wait
for stage in $failed; do
	took=$(($(cat "$out/$stage.end") - $(cat "$out/$stage.start")))
	echo "==================== stage $stage: FAILED after ${took}s ===================="
	cat "$out/$stage.log"
done

# Leave nothing but caches on the volume the promoter may keep.
leftover=$(docker ps -aq)
if [ -n "$leftover" ]; then
	# shellcheck disable=SC2086 # a list of IDs
	docker rm -f $leftover >/dev/null 2>&1 || true
fi

if [ "$event" = push ]; then
	# Old CI images and the build cache would otherwise fill the volume the
	# promoter snapshots until master runs fail.
	for old in $(docker image ls --format '{{.Repository}}:{{.Tag}}' {{PROJECT}}-ci); do
		if [ "$old" != "$image" ]; then docker image rm "$old" >/dev/null || true; fi
	done
	docker image prune -f >/dev/null
	docker builder prune -f --keep-storage "${CI_BUILD_CACHE_BUDGET:-8GB}" >/dev/null
	docker system df
fi

# The stage table: result, wall time, the stage container's peak memory and
# its average CPU use. Watch the totals over time: a slow drift up is a
# project-health problem worth an issue before it costs every PR.
echo
printf '%-14s %-7s %6s %12s %6s\n' stage result time "peak memory" cores
for stage in $stages; do
	took=$(($(cat "$out/$stage.end") - $(cat "$out/$stage.start")))
	result=passed
	[ "$(cat "$out/$stage.exit")" = 0 ] || result=failed
	mem=$(awk '/^memory_peak/ { print $2 }' "$out/$stage.stats" 2>/dev/null || echo 0)
	cpu=$(awk '/^usage_usec/ { print $2 }' "$out/$stage.stats" 2>/dev/null || echo 0)
	awk -v s="$stage" -v r="$result" -v t="$took" -v m="${mem:-0}" -v c="${cpu:-0}" 'BEGIN {
		mem = (m > 0) ? sprintf("%.1f GiB", m / 1073741824) : "-"
		cores = (t > 0) ? c / 1e6 / t : 0
		printf "%-14s %-7s %5ds %12s %6.1f\n", s, r, t, mem, cores
	}'
done
echo "VM peak memory used: $(($(cat "$peak_file") / 1024)) MiB (page cache excluded)"
echo "all stages done after $(elapsed)s"
if [ -n "$failed" ]; then
	echo "failed stages:$failed" >&2
	exit 1
fi
