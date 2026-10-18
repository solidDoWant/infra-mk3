#!/usr/bin/env bash
# Runs the project-manager agent (docs/agents/project-manager.md) in a restart
# loop. Each iteration is one headless Claude Code session = one PM cycle; the
# PM keeps its state in .pm/state.md and on GitHub, so a crash, VM restart, or
# usage-limit stop only costs the in-flight cycle.
#
# Control files (in .pm/):
#   STOP   - exit the loop before starting the next cycle.
#   PAUSE  - sleep (re-checking every minute) until the file is removed.
#
# Per-cycle transcripts land in $PM_LOG_DIR (default ~/.pm-logs) as
# stream-json, plus a one-line summary per cycle in $PM_LOG_DIR/cycles.log.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${PM_LOG_DIR:-$HOME/.pm-logs}"
MODEL="${PM_MODEL:-opus}"
PROMPT='You are the {{PROJECT}} project manager. Read docs/agents/project-manager.md and follow it exactly: resume from .pm/state.md, run one cycle, record progress, then exit.'

mkdir -p "$LOG_DIR" "$REPO_DIR/.pm"
cd "$REPO_DIR"

idle_backoff=60
while true; do
  if [ -e .pm/STOP ]; then
    echo "$(date -Is) STOP file present; exiting" | tee -a "$LOG_DIR/cycles.log"
    exit 0
  fi
  while [ -e .pm/PAUSE ]; do sleep 60; done

  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  log="$LOG_DIR/cycle-$ts.jsonl"
  start=$(date +%s)
  # ~/.local/bin goes first again inside the dev shell so the coder gh wrapper
  # (fresh GitHub token per call) wins over anything the shell puts on PATH.
  nix develop "$REPO_DIR" --command env PATH="$HOME/.local/bin:$PATH" claude -p "$PROMPT" \
    --dangerously-skip-permissions \
    --model "$MODEL" \
    --output-format stream-json --verbose \
    >"$log" 2>"$LOG_DIR/cycle-$ts.stderr"
  rc=$?
  duration=$(( $(date +%s) - start ))

  result="$(jq -r 'select(.type == "result") | .result // .subtype' "$log" 2>/dev/null | tail -n 1)"
  cost="$(jq -r 'select(.type == "result") | .total_cost_usd // empty' "$log" 2>/dev/null | tail -n 1)"
  printf '%s rc=%s duration=%ss cost=%s result=%q\n' "$(date -Is)" "$rc" "$duration" "${cost:-?}" "${result:0:300}" >>"$LOG_DIR/cycles.log"

  if grep -qiE 'usage limit|rate.?limit|overloaded|429' "$log" "$LOG_DIR/cycle-$ts.stderr" 2>/dev/null && [ "$rc" -ne 0 ]; then
    sleep_for=900
  elif [ "$rc" -ne 0 ]; then
    sleep_for=120
  elif grep -q 'PM-IDLE' <<<"$result"; then
    sleep_for=$idle_backoff
    idle_backoff=$(( idle_backoff * 2 > 3600 ? 3600 : idle_backoff * 2 ))
  else
    idle_backoff=60
    sleep_for=10
  fi

  # Keep the newest 300 transcripts.
  ls -1t "$LOG_DIR"/cycle-* 2>/dev/null | tail -n +601 | xargs -r rm -f
  sleep "$sleep_for"
done
