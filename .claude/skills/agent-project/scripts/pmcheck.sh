#!/usr/bin/env bash
# Summarize PM loop health inside a coder workspace.
# Usage: pmcheck.sh WORKSPACE REPO_DIR [N_RECENT_TOOL_CALLS]
#   e.g. pmcheck.sh vault-sync-vm /workspace/vault-sync 25
set -uo pipefail
ws="$1" repo="$2" n="${3:-15}"

# coder ssh prints its own timestamped startup lines ("2026-10-18 02:34:52.710Z ...");
# drop only those, not the loop's ISO-8601 cycles.log lines.
coder ssh "$ws" -- "
cd '$repo'
echo '== tmux'; tmux ls 2>&1
echo '== cycles.log (tail)'; tail -n 8 ~/.pm-logs/cycles.log 2>/dev/null | cut -c1-300
f=\$(ls -1t ~/.pm-logs/cycle-*.jsonl 2>/dev/null | head -1)
echo \"== latest: \$f (\$(stat -c %y \"\$f\" 2>/dev/null | cut -c1-19))\"
tail -n 3 \"\${f%.jsonl}.stderr\" 2>/dev/null
jq -r 'select(.type==\"assistant\") | .message.content[]? | if .type==\"text\" then \"TEXT: \"+(.text|.[0:300]) elif .type==\"tool_use\" then \"TOOL: \"+.name+\" \"+((.input.description // .input.command // .input.prompt // .input.file_path // \"\")|tostring|.[0:160]) else empty end' \"\$f\" 2>/dev/null | tail -n $n
echo '== state.md'; head -c 1500 .pm/state.md 2>/dev/null
echo; echo '== main checkout / worktrees'; git status -sb | head -1; git worktree list
echo '== mem/disk'; free -g | sed -n 2p; df -h '$repo' | tail -1; uptime
" 2>&1 | grep -v '^20..-..-.. ..:..:..\.[0-9]*Z'
