#!/usr/bin/env bash
# Runs `go test` with the given arguments. When GO_TEST_JSON names a file, it
# also writes the `go test -json` events there (for the acceptance
# scoreboard) and prints the plain test output as usual. The exit status is
# go test's.
#
#   GO_TEST_JSON=build/acceptance/results/go-unit.json scripts/ci/go-test-json.sh -race ./...
set -uo pipefail

if [[ -z "${GO_TEST_JSON:-}" ]]; then
	exec go test "$@"
fi

mkdir -p "$(dirname "$GO_TEST_JSON")"
go test -json "$@" | tee "$GO_TEST_JSON" | python3 -c '
import json
import sys

for line in sys.stdin:
    try:
        event = json.loads(line)
    except ValueError:
        sys.stdout.write(line)
        continue
    if event.get("Action") == "output":
        sys.stdout.write(event.get("Output", ""))
'
exit "${PIPESTATUS[0]}"
