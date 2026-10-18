Create a new GitHub issue for this repository. The argument(s) provided (if any) are a brief description or topic: `$ARGUMENTS`

---

## Step 1: Gather context

Read `SPEC.md` — it is the authoritative technical reference for package contracts, binary responsibilities, and configuration.

---

## Step 2: Scope the issue

Before drafting, assess whether you have enough information to write accurate, falsifiable acceptance criteria and meaningful technical context. Ask clarifying questions only for gaps that cannot be inferred from `$ARGUMENTS`, `SPEC.md`, or the codebase — things like: the motivation behind the work, explicit non-goals, dependencies on other issues, or constraints not captured in the spec.

If `$ARGUMENTS` already covers everything, skip straight to Step 3. If there are gaps, ask them all at once (not one at a time), then wait for the user's answers before proceeding.

Once the scope is clear, read any relevant source files that the issue will touch, to write accurate Technical Context.

---

## Step 3: Draft the issue

Using `$ARGUMENTS` and any answers from Step 2, produce a draft following this exact structure:

```markdown
## Summary

{1–3 sentences: what this work item does and why.}

## Acceptance Criteria

- [ ] **Given** {precondition}, **when** {action}, **then** {observable outcome}.
...

## Technical Context

- Depends on: {issue numbers, or "none"}
- {Key constraints, env vars, package contracts, file paths, or design decisions an implementer needs.}
- {Add as many bullets as needed; omit this section if truly empty.}

## Non-Goals

- {What is explicitly out of scope for this issue.}
```

Rules for the draft:
- Title uses conventional commit format: `type(scope): short description` (e.g. `feat(engine): resume interrupted uploads`).
- Acceptance criteria describe **observable behavior only** — no implementation details.
- Every criterion must be falsifiable: a broken implementation must cause it to fail.
- Technical Context contains everything an implementer needs that isn't obvious from the code or spec — dependencies, env var names, interface contracts, ordering constraints.
- Non-Goals prevent scope creep; always include at least one.
- Issues that add a guard, fence, lint rule, CI check, or other protective mechanism must state its **threat model** in Technical Context (what it must stop, and what it explicitly does not try to stop) so reviews have a boundary.
- Do not invent acceptance criteria that weren't requested or implied. Ask if unsure.

---

## Step 4: Review loop

Present the draft title and body to the user. Then:

- If the user requests changes: revise and re-present. Repeat until approved.
- If the user approves (says "looks good", "create it", "ship it", or similar): proceed to Step 5.
- If the user asks a question you cannot answer from the codebase or spec: answer it if you can, or flag it and ask for clarification before continuing.

---

## Step 5: Create the issue

Once approved, write the issue body to a temp file and create the issue:

```
body_file=$(mktemp)
cat > "$body_file" << 'EOF'
{body}
EOF
gh issue create --title "{title}" --body-file "$body_file"
rm "$body_file"
```

Print the new issue URL.
