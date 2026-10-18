## Shell Hygiene (agents)

The worktree-isolation guard rejects many compound shell commands, and failed tool calls waste time. In this VM:

- Run one simple command per Bash call, from inside your worktree (`cd` into it first). Don't chain git commands with pipes, loops, or `bash -c`.
- Put multi-step logic in a script file under your worktree (or `/tmp`) and run that.
- Prefix toolchain commands with `nix develop -c` (`go`, `node`, `npm`, `buf`, `golangci-lint` are not on the bare PATH). `python3` is available inside the dev shell only.
- Don't `sleep` to wait; use `gh pr checks --watch`, `gh run watch`, or the Monitor tool (load it with ToolSearch first).
- A branch can be checked out in only one worktree. If git says it is in use, check it out detached or report to the project manager — never delete another agent's worktree.

