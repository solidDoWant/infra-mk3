#!/usr/bin/env bash
# Waits up to SECONDS (default 230) for every CI check on PR to finish, then
# prints them. Exit status: 0 = all finished and passing, 1 = finished with a
# failure, 3 = still running (call again), 2 = usage error. Use this instead
# of `gh pr checks --watch` (see wait-for.sh for why waits are bounded).
#
# CI counts as still running until at least one required check (branch
# protection's, e.g. the `checks` aggregator job) is reported for the PR's
# head: right after a push the only check listed may be one that finishes at
# once (CodeRabbit), and `checks` is only registered once the jobs it needs
# have finished. A PR whose base branch requires no checks therefore never
# exits 0; it exits 3 at the deadline.
#
# The run ends by the deadline whatever GitHub does (a merge state of UNKNOWN,
# a new head with no checks yet, a stalled API call): each `gh` call is killed
# after WAIT_CI_GH_TIMEOUT seconds (default 30) or when the deadline passes,
# whichever is first, and the wait between polls (WAIT_CI_INTERVAL seconds,
# default 15) stops at the deadline. The first poll always runs, giving each
# call at least 1 second, so a 0-second deadline still checks once.
#
#   ./scripts/agents/wait-ci.sh 287
set -uo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 PR [SECONDS]" >&2
  exit 2
fi
pr=$1 limit=${2:-230} gh_cap=${WAIT_CI_GH_TIMEOUT:-30} interval=${WAIT_CI_INTERVAL:-15}
deadline=$(( $(date +%s) + limit ))
first=1

# bounded_gh ARGS...: runs gh, killed (with its children) after gh_cap seconds
# or at the deadline, whichever is first. Fails without running gh once the
# deadline has passed, except on the first poll.
bounded_gh() {
  local seconds=$(( deadline - $(date +%s) ))
  [ "$first" -eq 1 ] && [ "$seconds" -lt 1 ] && seconds=1
  [ "$seconds" -gt "$gh_cap" ] && seconds=$gh_cap
  [ "$seconds" -gt 0 ] || return 124
  timeout -k 1 "$seconds" gh "$@"
}

while :; do
  checks=$(bounded_gh pr checks "$pr" --json name,bucket 2>/dev/null)
  # gh fails with nothing on stdout while no required check is reported.
  required=$(bounded_gh pr checks "$pr" --required --json name,bucket 2>/dev/null)
  first=0
  if [ -n "$checks" ] && [ -n "$required" ] &&
    [ "$(jq 'length' <<<"$required")" -gt 0 ] &&
    [ "$(jq -s '[.[][] | select(.bucket == "pending")] | length' <<<"$checks$required")" -eq 0 ]; then
    jq -r '.[] | "\(.bucket)\t\(.name)"' <<<"$checks"
    [ "$(jq -s '[.[][] | select(.bucket == "fail" or .bucket == "cancel")] | length' <<<"$checks$required")" -eq 0 ]
    exit $?
  fi
  left=$(( deadline - $(date +%s) ))
  if [ "$left" -le 0 ]; then
    echo "wait-ci: PR $pr still has pending or unregistered required checks after ${limit}s" >&2
    exit 3
  fi
  sleep $(( left < interval ? left : interval ))
done
