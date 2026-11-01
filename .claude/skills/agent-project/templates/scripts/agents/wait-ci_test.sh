#!/usr/bin/env bash
# Tests scripts/agents/wait-ci.sh against a fake `gh` that reports a fixed set
# of checks. Most cases run with a 0-second deadline, so the script polls once
# and never sleeps; the bounded-time cases at the end use a few seconds.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wait-ci.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The fake gh prints $FAKE_ALL for `gh pr checks PR --json ...` and
# $FAKE_REQUIRED for `gh pr checks PR --required --json ...`. Like the real
# gh, it fails with a message on stderr and nothing on stdout when no
# required check has been reported. With FAKE_HANG set it never answers, like
# a stalled API call; with FAKE_HANG_ONCE set to a path, only the first call
# (the one that creates that file) hangs.
mkdir "$work/bin"
cat >"$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
[[ $1 == pr && $2 == checks ]] || { echo "fake gh: unexpected: $*" >&2; exit 2; }
if [[ -n ${FAKE_HANG_ONCE:-} && ! -e $FAKE_HANG_ONCE ]]; then
	: >"$FAKE_HANG_ONCE"
	sleep 1000
fi
if [[ -n ${FAKE_HANG:-} ]]; then
	sleep 1000
fi
for arg in "$@"; do
	if [[ $arg == --required ]]; then
		if [[ -z $FAKE_REQUIRED || $FAKE_REQUIRED == "[]" ]]; then
			echo "no required checks reported on the 'x' branch" >&2
			exit 1
		fi
		printf '%s\n' "$FAKE_REQUIRED"
		exit 0
	fi
done
printf '%s\n' "$FAKE_ALL"
EOF
chmod +x "$work/bin/gh"

# run NAME WANT ALL REQUIRED: runs wait-ci.sh and checks its exit status.
run() {
	local name=$1 want=$2 got=0
	FAKE_ALL=$3 FAKE_REQUIRED=$4 PATH="$work/bin:$PATH" \
		"$script" 1 0 >"$work/out" 2>&1 || got=$?
	if [[ $got -ne $want ]]; then
		echo "FAIL: $name: exit $got, want $want" >&2
		cat "$work/out" >&2
		exit 1
	fi
}

coderabbit='{"name":"CodeRabbit","bucket":"pass"}'
unit_pass='{"name":"unit","bucket":"pass"}'
unit_fail='{"name":"unit","bucket":"fail"}'
unit_pending='{"name":"unit","bucket":"pending"}'
checks_pass='{"name":"checks","bucket":"pass"}'
checks_fail='{"name":"checks","bucket":"fail"}'

run "fresh push: only a finished non-required check" 3 "[$coderabbit]" ""
run "every job done but the required aggregator not registered yet" 3 "[$coderabbit,$unit_pass]" ""
run "no checks at all" 3 "" ""
run "a non-required check still pending" 3 "[$coderabbit,$unit_pending,$checks_pass]" "[$checks_pass]"
run "required checks passed" 0 "[$coderabbit,$unit_pass,$checks_pass]" "[$checks_pass]"
run "required check failed" 1 "[$coderabbit,$unit_fail,$checks_fail]" "[$checks_fail]"
run "a non-required check failed" 1 "[$coderabbit,$unit_fail,$checks_pass]" "[$checks_pass]"

# run_timed NAME WANT SECONDS MAX ALL REQUIRED [ENV...]: runs wait-ci.sh with
# a SECONDS deadline and checks it exits WANT within MAX seconds. The run is
# killed a few seconds after MAX so an unbounded wait fails instead of hanging.
run_timed() {
	local name=$1 want=$2 limit=$3 max=$4 all=$5 required=$6 got=0 start elapsed
	shift 6
	start=$(date +%s)
	timeout -k 1 $((max + 3)) env FAKE_ALL="$all" FAKE_REQUIRED="$required" \
		PATH="$work/bin:$PATH" "$@" "$script" 1 "$limit" >"$work/out" 2>&1 || got=$?
	elapsed=$(($(date +%s) - start))
	if [[ $got -ne $want || $elapsed -gt $max ]]; then
		echo "FAIL: $name: exit $got after ${elapsed}s, want $want within ${max}s" >&2
		cat "$work/out" >&2
		exit 1
	fi
}

# A new head (or a PR whose merge state is UNKNOWN) has no checks yet: gh
# fails for both calls on every poll until the deadline.
run_timed "new head with no checks yet" 3 3 6 "" ""
run_timed "new head with no checks yet, short poll interval" 3 3 6 "" "" WAIT_CI_INTERVAL=1
# A gh call that never returns is cut off at the deadline.
run_timed "hung gh with a short deadline" 3 3 6 "" "" FAKE_HANG=1
# Even with a 0-second deadline the single poll is bounded.
run_timed "hung gh with a 0-second deadline" 3 0 5 "" "" FAKE_HANG=1
# A stalled call is cut off at the per-call cap, so a later poll still sees
# the checks finish well before the deadline.
run_timed "one stalled gh call under the per-call cap" 0 60 10 \
	"[$coderabbit,$unit_pass,$checks_pass]" "[$checks_pass]" \
	FAKE_HANG_ONCE="$work/hung" WAIT_CI_GH_TIMEOUT=1 WAIT_CI_INTERVAL=1

if "$script" >/dev/null 2>&1; then status=0; else status=$?; fi
[[ $status -eq 2 ]] || { echo "FAIL: no arguments: exit $status, want 2" >&2; exit 1; }

echo "wait-ci_test: ok"
