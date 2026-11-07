## Names and comments: no tracking IDs

**Owner rule.** Code is read long after the plan that produced it is forgotten. Tracking IDs mean nothing to that reader.

- **Never put these in code, tests, scripts, the chart or the user and admin docs:**
  - acceptance IDs (`AC-4-16`);
  - phase or milestone numbers ("phase 3");
  - design-document row or section numbers ("row 247", "§5");
  - issue or PR numbers (`#354`).
- **Name tests after the behaviour they check.** Write `TestDenyAppliesAtOnceAcrossReplicas`, never `TestAC4_16`. Subtest names are plain sentences.
- **Tie a test to an acceptance scenario only in the checklist.** Each automated scenario in `docs/acceptance/phase-N.md` has a `Tests:` line that names its tests. The scoreboard, the shard selection, the test guard and the release gate read that line. To link a new test, add it there.
- **Comments explain the reason, not the history.** Write "older gateways don't delete allow entries when they end a session, so the leader cleans them up", not "row 247" or "see #430".
- **The records keep their IDs.** `docs/acceptance/`, `docs/design/`, `docs/agents/` and the changelog are the project's records, and they keep their IDs and links.
- **`make lint` enforces this.** It fails on these patterns outside the records:
  - `AC-\d+-\d+`;
  - `func TestAC`;
  - `[Pp]hase \d`;
  - `row \d{2,}`;
  - `§\s?\d`;
  - `#\d{2,}`.

  Its few allowed exceptions are kept in one list, each with a reason.
