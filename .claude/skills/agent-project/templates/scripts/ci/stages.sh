#!/bin/sh
# Runs the CI stages on Tekton, all at the same time, each in its own
# container of the CI image (scripts/ci/ci-image.sh), inside the docker Task's
# dind. Runs in the docker Task's step, from the checkout at $WS/src, where WS
# is the Task's workspace: the step and dockerd see it at the same path.
#
#   CI_REPO=<owner/name> scripts/ci/stages.sh pull_request|push
#   CI_REPO=<owner/name> RELEASE_VERSION=<version> scripts/ci/stages.sh release
#
# A pull request runs the stages its changes need (scripts/ci/changes.py); a
# push runs them all and then cleans the Docker storage that the cache
# promoter keeps. A release runs one stage, release, which publishes the
# images and the chart of RELEASE_VERSION (scripts/ci/publish-release.sh). The script writes $WS/ci/stages.json, each stage's name,
# result, time and failure report (scripts/ci/stages-report.py), also to the
# file DOCKER_TASK_OUTPUT names (the docker Task's result, read by report), and
# exits non-zero after writing it when a stage failed, so the run fails even if
# the result is lost on its way to the report task (which still reads the
# result of the failed task and gives each stage its check run).
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

# The run's CPU budget: the dind sidecar's CPU request. The pod has no CPU
# limit (cluster policy), so without a cap the stages, which all start at once
# and each size themselves to every CPU they see, take the whole node and
# starve the other runs on it. Every stage container is pinned to the same
# CI_CPUS CPUs, the least busy run of them: the stages share them, a stage that ends leaves its share to
# the others, and the run never uses more. GOMAXPROCS is set to the budget too;
# go test -p, go build -p, golangci-lint's concurrency and the fuzz workers
# default to it or to the CPU affinity. The kind node of e2e is not pinned, so
# it boots on the VM's other CPUs.
cpus="${CI_CPUS:-8}"
case "$cpus" in
'' | *[!0-9]* | 0*)
	echo "CI_CPUS must be a positive whole number of CPUs, not '$cpus'" >&2
	exit 1
	;;
esac
available=$(docker run --rm --entrypoint /bin/sh "$image" -c 'cat /sys/fs/cgroup/cpuset.cpus.effective 2>/dev/null || cat /sys/devices/system/cpu/online')
# A VM with fewer CPUs than the budget gives the stages all it has.
# Other runs on the node pin their stages too, so the stages take the CPUs the
# node used least in the last second, not always the first ones.
stat_dir=$(mktemp -d)
cp /proc/stat "$stat_dir/before"
sleep 1
cp /proc/stat "$stat_dir/after"
pinned=$(./scripts/ci/cpuset-first.sh "$available" "$cpus" "$stat_dir/before" "$stat_dir/after" "$(hostname)")
rm -rf "$stat_dir"
cpuset=$(echo "$pinned" | head -n 1)
busy=$(echo "$pinned" | sed -n 2p)
cpus=${cpuset#* }
cpuset=${cpuset% *}
echo "CPU budget: $cpus CPUs (CI_CPUS=${CI_CPUS:-unset}, default 8); stages pinned to CPUs $cpuset of $available; busy ticks per CPU in the last second: ${busy:-unknown}"

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
	./scripts/ci/changed-files.sh >"$ci/changed-files"
	stages=$(in_image ./scripts/ci/changes.py pull_request <"$ci/changed-files")
fi

# What a stage needs to reach the container registries like this step's own
# Docker CLI. The CI cluster sends registry traffic through its registrygate
# (the owner's registry proxy, not part of this project): the system CAs plus
# registrygate's CA (dockerd's certs.d, the same CA for every intercepted
# host), its Docker credential helper, its token and the Docker configuration
# that names it. An intercepted task pod also adds githubgate's interceptor CAs
# (scripts/ci/ca-bundle.sh): the stages share the pod's network, so their GitHub
# traffic goes through the interceptor.
./scripts/ci/ca-bundle.sh "$ci/ca-bundle.crt"
docker run --rm -v /etc/docker/certs.d:/certsd:ro --entrypoint /bin/sh "$image" \
	-c 'f=$(ls /certsd/*/ca.crt 2>/dev/null | head -n1); if [ -n "$f" ]; then cat "$f"; fi' >>"$ci/ca-bundle.crt"
if [ -x /opt/registrygate/docker-credential-registrygate ]; then
	cp /opt/registrygate/docker-credential-registrygate "$ci/bin/"
	cp /var/run/secrets/registrygate/token "$ci/token"
fi
if [ -f "${HOME:-/nonexistent}/.docker/config.json" ]; then
	cp "$HOME/.docker/config.json" "$ci/docker/config.json"
fi

# Every run checks, from a stage container in the stage environment
# (stage-env.sh), the way the release stage reaches GitHub, that one read-only
# GitHub API request from Python and one from curl get an HTTP response over
# verified TLS, so a broken bundle or interception fails a
# pull request, not a release. Any status passes: a policy may deny the request
# (the release ServiceAccount's does), and that still proves the TLS chain.
repo="${CI_REPO:?CI_REPO must name the repository (owner/name)}"
if ! docker run --rm --network host -v "$WS:$WS" -w "$src" -e CI_CA="$ci/ca-bundle.crt" "$image" \
	bash -c 'source /etc/devshell.sh && source ./scripts/ci/stage-env.sh && exec ./scripts/ci/github-api-check.py "$1"' bash "$repo"; then
	echo "a stage container cannot reach the GitHub API over verified TLS; see above" >&2
	exit 1
fi

if [ -z "$stages" ]; then
	echo "no stage needs to run for these changes"
	echo '[]' >"$ci/stages.json"
	if [ -n "${DOCKER_TASK_OUTPUT:-}" ]; then cp "$ci/stages.json" "$DOCKER_TASK_OUTPUT"; fi
	exit 0
fi
echo "stages: $stages"

# The Go caches live on dockerd's volume, which the cache promoter keeps after
# a successful master push run.
docker volume create gomod >/dev/null
docker volume create gobuild >/dev/null

# check-generate rewrites the generated files in place while the other stages
# build them, so it gets its own copy of the tree, mounted at the same path so
# that Go's build cache entries still match.
generate_src="$WS/generate-src"

command_of() {
	case "$1" in
	lint) echo 'make lint' ;;
	unit) echo 'make test && make build' ;;
	# Two workers per target: all stages share the run's CPU budget, and four
	# workers per target starved the lint and e2e stages.
	fuzz) echo 'make test-fuzz FUZZ_PARALLEL=2' ;;
	generate) echo 'make check-generate' ;;
	integration) echo 'make test-integration' ;;
	e2e) echo 'make test-e2e' ;;
	# Not a reported stage: builds the e2e images while the e2e stage creates
	# its kind cluster.
	e2e-images) echo './test/e2e/build-images.sh' ;;
	docs)
		# The style report is advisory.
		if [ "$event" = pull_request ]; then
			echo 'make docs-check && ./scripts/check-tracking-ids.py && { ./scripts/docs/style_report.sh origin/master || true; }'
		else
			echo 'make docs-check && ./scripts/check-tracking-ids.py'
		fi
		;;
	scoreboard) echo './scripts/acceptance-scoreboard_test.py' ;;
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
	if [ "$stage" = generate ]; then
		rm -rf "$generate_src"
		git clone -q --no-hardlinks "$src" "$generate_src"
		git -C "$generate_src" checkout -q --detach "$(git rev-parse HEAD)"
		mount="$mount -v $generate_src:$src"
	fi
	# The e2e kind nodes pull through the CI cluster's registrygate with the
	# config CI provides.
	case "$stage" in
	e2e) [ -x /run/ci-kind/bin/ci-kind-config ] && mount="$mount -v /run/ci-kind:/run/ci-kind:ro -v /opt/ci-kind:/opt/ci-kind:ro" ;;
	esac
	date +%s >"$out/$stage.start"
	(
		status=0
		# shellcheck disable=SC2086 # $mount is a list of options
		docker run --rm --name "stage-$stage" --network host $mount -w "$src" \
			--cpuset-cpus "$cpuset" -e GOMAXPROCS="$cpus" \
			-v gomod:/cache/gomod -v gobuild:/cache/gobuild \
			-e GOMODCACHE=/cache/gomod -e GOCACHE=/cache/gobuild/go \
			-e GOLANGCI_LINT_CACHE=/cache/gobuild/golangci-lint \
			-e DOCKER_HOST=tcp://127.0.0.1:2375 -e DOCKER_CONFIG="$ci/docker" \
			-e REGISTRYGATE_HOSTS="${REGISTRYGATE_HOSTS:-}" -e REGISTRYGATE_TOKEN_FILE="$ci/token" \
			-e CI_BIN="$ci/bin" -e CI_CA="$ci/ca-bundle.crt" -e CI_STATS="$out/$stage.stats" \
			-e E2E_CLUSTER="{{PROJECT}}-ci" \
			-e E2E_IMAGES_EXIT_FILE="${E2E_IMAGES_EXIT_FILE:-}" -e E2E_IMAGES_LOG="${E2E_IMAGES_LOG:-}" \
			-e E2E_DISCARD_CLUSTER=1 \
			-e RELEASE_VERSION="${RELEASE_VERSION:-}" -e CI_REPO="${CI_REPO:-}" \
			-e STAGE_COMMAND="$(command_of "$stage")" \
			"$image" bash -c '
				source /etc/devshell.sh
				source ./scripts/ci/stage-env.sh
				export PATH="$CI_BIN:$PATH"
				git config --global --add safe.directory "*"
				status=0
				bash -c "set -e; $STAGE_COMMAND" || status=$?
				# The container cgroup: this stage alone (the kind node of e2e
				# is a container of its own).
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

# The e2e stage needs the e2e images, but only once its kind cluster exists
# (test/e2e/up.sh). Build the images on the shared dockerd at the same time as
# the e2e stage creates its cluster; up.sh waits for the build's
# exit file before it loads the images, and fails with the build's log when the
# build failed. The build's own log and time stay out of the stage table.
e2e_stages=""
other_stages=""
for stage in $stages; do
	case "$stage" in
	e2e) e2e_stages="$e2e_stages $stage" ;;
	*) other_stages="$other_stages $stage" ;;
	esac
done
# The e2e stage goes first, so its kind cluster starts before the CPU-heavy
# stages (race tests, fuzzers, linters) compete for the cores.
if [ -n "$e2e_stages" ]; then
	rm -f "$out/e2e-images.exit"
	E2E_IMAGES_EXIT_FILE="$out/e2e-images.exit"
	E2E_IMAGES_LOG="$out/e2e-images.log"
	export E2E_IMAGES_EXIT_FILE E2E_IMAGES_LOG
	for stage in $e2e_stages; do start_stage "$stage"; done
	start_stage e2e-images
fi
for stage in $other_stages; do
	start_stage "$stage"
done
echo "started after $(elapsed)s: $stages"

# Prints each passed stage's log as one block as soon as it ends, and the
# failed ones last, so the failure is at the end of the step log.
printed=""
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
		printed="$printed $stage"
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

# Leave nothing but caches on the volume the promoter may keep: a kind
# cluster left behind is only its node containers.
leftover=$(docker ps -aq)
if [ -n "$leftover" ]; then
	# shellcheck disable=SC2086 # a list of IDs
	docker rm -f $leftover >/dev/null 2>&1 || true
fi

if [ "$event" = push ]; then
	date +%s >"$out/cleanup.start"
	status=0
	# e2e-images.sh needs bash and helm, which only the CI image has.
	in_image ./scripts/ci/e2e-images.sh --node </dev/null >"$out/keep-images" 2>"$out/cleanup.log" || status=$?
	if [ "$status" = 0 ]; then
		./scripts/ci/cleanup.sh "$image" "$out/keep-images" >>"$out/cleanup.log" 2>&1 || status=$?
	fi
	date +%s >"$out/cleanup.end"
	echo "$status" >"$out/cleanup.exit"
	echo "==================== cleanup (exit $status) ===================="
	cat "$out/cleanup.log"
	stages="$stages cleanup"
	if [ "$status" != 0 ]; then failed="$failed cleanup"; fi
fi

# shellcheck disable=SC2086 # a list of stage names
in_image ./scripts/ci/stages-report.py "$out" "$ci/stages.json" $stages
if [ -n "${DOCKER_TASK_OUTPUT:-}" ]; then cp "$ci/stages.json" "$DOCKER_TASK_OUTPUT"; fi
echo "VM peak memory used: $(($(cat "$peak_file") / 1024)) MiB (page cache excluded)"
echo "all stages done after $(elapsed)s"
if [ -n "$failed" ]; then
	echo "failed stages:$failed" >&2
	exit 1
fi
