#!/usr/bin/env bash
# Waits up to SECONDS (default 230) for REGEX to appear in FILE, then prints
# the last 20 lines of FILE. Exit status: 0 = found, 3 = not yet (call again),
# 2 = usage error.
#
# Agents must never block a single tool call for more than ~4 minutes:
# subagent prompt caches expire after 5 minutes, and a resumed turn after a
# longer gap re-writes the whole context. Poll long-running work with this
# helper in a loop of separate calls instead of one long `until ... sleep`.
#
#   ./scripts/agents/wait-for.sh /tmp/w42/sim.log '^(ok|FAIL)\s'
set -uo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 FILE REGEX [SECONDS]" >&2
  exit 2
fi
file=$1 regex=$2 limit=${3:-230}
deadline=$(( $(date +%s) + limit ))

while :; do
  if [ -f "$file" ] && grep -qE -- "$regex" "$file"; then
    tail -n 20 "$file"
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "wait-for: no match for /$regex/ in $file after ${limit}s; last output:" >&2
    [ -f "$file" ] && tail -n 5 "$file" >&2
    if [ -f "$file" ]; then
      idle=$(( $(date +%s) - $(stat -c %Y "$file") ))
      echo "wait-for: $file last written ${idle}s ago" >&2
    fi
    exit 3
  fi
  sleep 5
done
