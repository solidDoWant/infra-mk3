## Shell Hygiene (agents)

The worktree-isolation guard rejects many compound shell commands, and failed tool calls waste time. In this VM:

- Run one simple command per Bash call, from inside your worktree (`cd` into it first). Don't chain git commands with pipes, loops, or `bash -c`.
- Put multi-step logic in a script file under your worktree (or `/tmp`) and run that.
- The dev shell is already loaded into every Bash call (`.pm/devenv.sh` via `CLAUDE_ENV_FILE`): run `go`, `node`, `npm`, `buf`, `golangci-lint`, `make`, `python3` directly. **Don't** wrap commands in `nix develop -c` or `bash -c`.
- **Never block a single tool call for more than ~4 minutes.** Subagent prompt caches expire after 5 minutes, so a turn that resumes after a longer wait re-writes your whole context. Start anything long (simulations, integration/e2e suites, `-count=50` runs) in the background with output to a log file, then poll it with `./scripts/agents/wait-for.sh <log> '<regex>'` (≤230 s per call; exit 3 means call it again). Wait for CI with `./scripts/agents/wait-ci.sh <PR>`, not `gh pr checks --watch` or `until … sleep` loops.
- **Hangs:** bound every test command (`timeout 15m …`; `make test-sim` defaults to `SIM_TIMEOUT=15m`). If a run's log has not grown for 5 minutes, treat it as hung: kill it (`kill -QUIT` the Go test binary first to get a goroutine dump), file a `bug` issue with the seed and the dump, and move on — don't wait out the timeout.
- A branch can be checked out in only one worktree. If git says it is in use, check it out detached or report to the project manager — never delete another agent's worktree.

