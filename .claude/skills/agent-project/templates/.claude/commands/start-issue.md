> **Interactive (human-driven) use.** Agents dispatched by the project manager follow `.claude/agents/issue-worker.md` instead, which skips the human plan-approval loop below.

Load the GitHub issue number provided as `$ISSUE_NUMBER`.

Run: `gh issue view $ISSUE_NUMBER --json title,body,labels,comments`
Read `.claude/tasks/$ISSUE_NUMBER.md` if it exists.

---

## Issue engagement (ongoing throughout all steps)

- **Answer questions**: Read all comments on the issue. If any commenter has asked a question that hasn't been answered, post a reply answering it before proceeding.
- **Ask questions**: If at any point you need information you cannot determine from the issue, codebase, or existing comments, post a question as an issue comment and ask the user to reply on the issue. Then stop and wait — do not proceed until you have an answer.
- Before stopping to wait for a reply: write your current state (what you've done, what you're waiting on, any decisions made so far) to `.claude/tasks/$ISSUE_NUMBER.md`, then inform the user: "I've posted a question on issue #$ISSUE_NUMBER. Please reply there and then re-run this command." When re-invoked, read that file to resume where you left off.

---

## Step 0: Size assessment

Assess whether the issue is large before doing anything else. It is large if any of the following are true:
- Would touch more than ~10 files
- Spans multiple services or modules
- Contains multiple independent acceptance criteria that don't share a code path
- Has significant ambiguity — missing technical context, unclear boundaries, or implementation approach not evident from the issue

**If large → decomposition path:**
1. If the scope is ambiguous, save current state to `.claude/tasks/$ISSUE_NUMBER.md`, post a focused clarifying question as an issue comment, and stop. Do not continue until answered.
2. Determine how to split the issue into sub-issues. Each sub-issue must be atomic (one concern, one service/module, ≤~10 files).
3. For each sub-issue, write a high-level plan: what it does, its acceptance criteria (Given/When/Then), and any dependencies on other sub-issues.
4. Create each sub-issue: `gh issue create -t "<type>(<scope>): <title>" -b "<body>"` using the standard template. Link it to the parent in its Technical Context section. Then attach it as a GitHub sub-issue of the parent: `gh api repos/{owner}/{repo}/issues/$ISSUE_NUMBER/sub_issues --method POST --field sub_issue_id=<child_issue_number>`.
5. Track dependencies between sub-issues using GitHub's issue dependencies feature — **do not build a markdown dependency table**. For each pair where sub-issue A must land before sub-issue B, add a `blocked by` link on B pointing to A. The API requires the blocker's database id (not its issue number); fetch it first, then add the dependency:
   ```
   BLOCKER_ID=$(gh api repos/{owner}/{repo}/issues/<blocker_number> --jq '.id')
   gh api repos/{owner}/{repo}/issues/<blocked_number>/dependencies/blocked_by --method POST --field issue_id=$BLOCKER_ID
   ```
6. Post a decomposition summary as a comment on the parent issue listing the sub-issues created. Do not include a markdown dependency or blocking table — the `blocked by` relationships from step 5 are the source of truth and GitHub renders them on each sub-issue.
7. Label the parent: `gh issue edit $ISSUE_NUMBER --add-label "status:decomposed"`
8. **Stop.** Present the decomposition to the user for review. Do not implement.

**If small → proceed with steps 1–6 below.**

---

## Steps 1–6: Implementation

1. **Self-assign**: `gh issue edit $ISSUE_NUMBER --add-label "status:in-progress"`. Also remove `status:todo` if it exists.

2. **Post plan**: Draft a brief written implementation plan covering: approach, files to change, and how each acceptance criterion will be satisfied. Do not use plan mode or take any action yet — just think and write. Then follow this approval loop:

   **If no plan exists yet in the task file:**
   - Post the plan as an issue comment using `gh api repos/{owner}/{repo}/issues/$ISSUE_NUMBER/comments --method POST --field body="..." --jq '.id'` and capture the returned comment ID.
   - Write the plan to `.claude/tasks/$ISSUE_NUMBER.md` with `status: pending-approval` and `plan_comment_id: <id>`.
   - Stop and ask the user (in the chat) to review the plan. Do not write any code until approved.

   **If a plan exists with `status: pending-approval`:**
   - Read all issue comments posted after the plan comment.
   - **Check for explicit approval**: a comment counts as approval only if it clearly and unconditionally says to proceed — e.g. "approved", "lgtm", "looks good, proceed", "go ahead". When in doubt, treat it as feedback, not approval.
   - If the latest relevant comment is explicit approval (and no subsequent comment adds new feedback): update the task file to `status: approved` and proceed to Step 3.
   - Otherwise (comment contains questions, change requests, or ambiguous language — or there are no new comments): treat as feedback. Revise the plan to address each piece of feedback, edit the existing plan comment in-place using `gh api repos/{owner}/{repo}/issues/comments/{plan_comment_id} --method PATCH --field body="..."` (read `plan_comment_id` from the task file), overwrite the plan in the task file (keeping `status: pending-approval`), and stop — ask the user to review the updated plan.

   **If the task file has `status: approved`:** skip directly to Step 3.

3. **Create branch**: Derive the branch name from the issue's conventional commit prefix and number: `feat/<scope>-<issue-number>` or `fix/<scope>-<issue-number>` (e.g. `fix/start-issue-12`). The scope is the parenthetical from the issue title (e.g. `fix(start-issue): ...` → scope is `start-issue`). Then run:
   ```
   gh issue develop $ISSUE_NUMBER -c --base master --name <branch-name>
   ```
   After creating the branch, record the branch name in `.claude/tasks/$ISSUE_NUMBER.md`.

4. **Implement**: Follow the approved plan from `.claude/tasks/$ISSUE_NUMBER.md` (and the corresponding issue comment) step by step. Do not deviate without checking with the user first. Work through acceptance criteria checkboxes, checking each off in the issue body as it passes.

5. **Open PR**: `gh pr create -t "<type>(<scope>): <title>" -b "Fixes #$ISSUE_NUMBER"`
   After creating the PR, record the PR number in `.claude/tasks/$ISSUE_NUMBER.md`.

6. **PR feedback loop**: On re-invocation after a PR is open, check for reviewer feedback:
   - Look up the PR number from `.claude/tasks/$ISSUE_NUMBER.md`, or find it via `gh pr list --head <branch> --json number,state --jq '.[0].number'`.
   - Fetch **all** review comments and general comments:
     - Inline review comments: `gh api repos/{owner}/{repo}/pulls/<PR>/comments`
     - Review summaries: `gh api repos/{owner}/{repo}/pulls/<PR>/reviews`
     - General PR comments: `gh api repos/{owner}/{repo}/issues/<PR>/comments`
   - Read `.claude/tasks/$ISSUE_NUMBER.md` and check the `replied_comment_ids` list (treat as `[]` if absent). Skip any comment whose ID is already in that list.
   - For each comment not yet in `replied_comment_ids`:
     1. Make the necessary code change(s) to address it.
     2. Commit with a descriptive message.
     3. Reply: inline review comment → `gh api repos/{owner}/{repo}/pulls/<PR>/comments/<id>/replies --method POST --field body=...`; otherwise `gh pr comment <PR> --body ...`.
     4. Append the comment ID to `replied_comment_ids` in `.claude/tasks/$ISSUE_NUMBER.md`.
   - After addressing all comments, push the updated branch.
   - If all threads are resolved or there are no unaddressed comments, report status to the user and stop.
   - **On merge**: delete the task file: `rm .claude/tasks/$ISSUE_NUMBER.md`.
