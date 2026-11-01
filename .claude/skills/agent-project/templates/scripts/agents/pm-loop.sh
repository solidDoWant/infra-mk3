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

# Headless `claude -p` only waits 10 minutes for background tasks (subagents)
# after the PM's last turn, then kills them -- which is what killed the cycle-2
# and cycle-7 workers. Wait up to 3 hours instead; a cycle is still bounded.
export CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS="${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-10800000}"

mkdir -p "$LOG_DIR" "$REPO_DIR/.pm"
cd "$REPO_DIR" || exit 1

# Claude Code's Bash tool runs each command from a snapshot of the login
# shell, so the dev shell's PATH does not reach agents even when claude itself
# runs under `nix develop`; agents then had to prefix commands with
# `nix develop -c`, which the worktree guard often rejects. Instead, export
# the dev shell as a file that Claude Code sources before every Bash command.
# ~/.local/bin goes last-but-first so the coder gh wrapper (fresh GitHub token
# per call) wins.
ENV_FILE="$REPO_DIR/.pm/devenv.sh"
refresh_env_file() {
  if nix print-dev-env "$REPO_DIR" >"$ENV_FILE.tmp" 2>"$LOG_DIR/devenv.stderr"; then
    # shellcheck disable=SC2016 # expanded when the file is sourced, not now
    printf 'export PATH="$HOME/.local/bin:$PATH"\n' >>"$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    echo "$(date -Is) WARNING: nix print-dev-env failed; keeping previous $ENV_FILE" >>"$LOG_DIR/cycles.log"
  fi
}
export CLAUDE_ENV_FILE="$ENV_FILE"

# Between cycles nothing else is running, so disk cleanup cannot break an
# in-flight build:
#   - the Go build cache grows ~1 GB/h under many worktrees; clear it past 15 GB
#   - each `nix develop` leaves a /tmp/nix-shell.* directory behind
#   - killed test runs leave their docker compose stack ({{PROJECT}}-test-PID) up
cleanup_between_cycles() {
  local gocache size_kb project pid
  gocache="$(bash -c "source '$ENV_FILE' >/dev/null 2>&1; go env GOCACHE" 2>/dev/null)"
  if [ -n "$gocache" ] && [ -d "$gocache" ]; then
    size_kb=$(du -sk "$gocache" 2>/dev/null | cut -f1)
    if [ "${size_kb:-0}" -gt $((15 * 1024 * 1024)) ]; then
      bash -c "source '$ENV_FILE' >/dev/null 2>&1; go clean -cache"
      echo "$(date -Is) cleanup: cleared Go build cache (${size_kb} KiB)" >>"$LOG_DIR/cycles.log"
    fi
  fi
  find /tmp -maxdepth 1 -name 'nix-shell.*' -mmin +360 -exec rm -rf {} + 2>/dev/null
  for project in $(docker ps -a --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | grep '^{{PROJECT}}-test-[0-9]*$' | sort -u); do
    pid=${project##*-}
    if ! kill -0 "$pid" 2>/dev/null; then
      docker ps -aq --filter "label=com.docker.compose.project=$project" | xargs -r docker rm -f >/dev/null
      docker network ls -q --filter "label=com.docker.compose.project=$project" | xargs -r docker network rm >/dev/null 2>&1
      echo "$(date -Is) cleanup: removed orphaned test stack $project" >>"$LOG_DIR/cycles.log"
    fi
  done
  docker volume prune -f >/dev/null 2>&1
}

idle_backoff=60
while true; do
  if [ -e .pm/STOP ]; then
    echo "$(date -Is) STOP file present; exiting" | tee -a "$LOG_DIR/cycles.log"
    exit 0
  fi
  while [ -e .pm/PAUSE ]; do sleep 60; done

  cleanup_between_cycles
  refresh_env_file

  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  log="$LOG_DIR/cycle-$ts.jsonl"
  start=$(date +%s)
  # The PM's own Bash calls source CLAUDE_ENV_FILE too; ~/.local/bin first so
  # the coder gh wrapper wins.
  PATH="$HOME/.local/bin:$PATH" claude -p "$PROMPT" \
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
