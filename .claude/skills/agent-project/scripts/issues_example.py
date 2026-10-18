# Issue definitions for solidDoWant/vault-sync. Each phase: an epic + sub-issues.
# "deps" are keys of issues that block this one.

def body(summary, ac, ctx, non_goals, deps_text=None):
    out = "## Summary\n\n" + summary.strip() + "\n\n## Acceptance Criteria\n\n"
    out += "\n".join("- [ ] " + a.strip() for a in ac) + "\n\n## Technical Context\n\n"
    out += "- Depends on: " + (deps_text or "{deps}") + "\n"
    out += "\n".join("- " + c.strip() for c in ctx) + "\n\n## Non-Goals\n\n"
    out += "\n".join("- " + n.strip() for n in non_goals) + "\n"
    return out

PHASES = {
    1: ("Phase 1 — Foundations", "Protocol schema, server core (store, blobs, revisions, auth, authz, realtime), sync-engine skeleton, simulation harness. SPEC.md §4–§6, §9.1–§9.2, §13."),
    2: ("Phase 2 — Single-user file sync", "Plugin engine + Obsidian adapter for desktop and Android, merge, conflicts, history/restore, export job, packaging. Dogfooding starts at the end of this phase. SPEC.md §6–§8, §11–§13."),
    3: ("Phase 3 — Vault sharing", "Membership management, invitations, roles in the UI, multi-user simulation. SPEC.md §9.2."),
    4: ("Phase 4 — End-to-end encryption", "Key hierarchy, encrypted content and paths, escrow for plaintext backups, cross-language vectors, crypto review. SPEC.md §9.3–§9.4."),
    5: ("Phase 5 — Live collaborative editing", "Yjs documents, exactly-once conversion, editor binding, awareness, compaction, encrypted updates. SPEC.md §10."),
}

ISSUES = []

def issue(key, phase, title, labels, summary, ac, ctx, non_goals, deps=()):
    ISSUES.append(dict(key=key, phase=phase, title=title, labels=labels, deps=list(deps),
                       body=body(summary, ac, ctx, non_goals)))

# ---------------------------------------------------------------- Phase 1
issue("proto", 1, "feat(proto): define sync API v1 schema", ["area:proto"],
      "Define the v1 ConnectRPC/protobuf API and the WebSocket frame messages that every later issue builds on (SPEC.md §4.1, §5, §6).",
      ["**Given** the schema, **when** `make generate` runs, **then** Go (`gen/`) and TypeScript (`plugin/src/gen/`) code is produced and `make check-generate` passes in CI.",
       "**Given** the schema, **when** `buf lint` runs, **then** it passes with the STANDARD rule set.",
       "**Given** the schema, **then** it defines RPCs for: creating/listing vaults; registering a device; listing changes since a sequence number (paginated); fetching a revision and its content reference; beginning, appending chunks to, and committing a blob upload; downloading a blob (ranged); committing a revision with a base revision id; and fetching document history.",
       "**Given** the schema, **then** it defines the realtime frame envelope (`oneof`) with at least `vault_changed{vault_id, seq}`, subscribe/unsubscribe, and an error frame, and reserves field ranges for Phase 5 Yjs update/awareness frames.",
       "**Given** the schema, **then** every document carries a `kind` (`blob`, `text`, `yjs`) and every encrypted-capable field (content reference, path) is `bytes`-compatible with E2EE (SPEC.md §9.3) without a breaking change."],
      ["Replace the placeholder `ServerInfoService` only if it no longer fits; keep `GetServerInfo` (unauthenticated) returning server and protocol version.",
       "Use protobuf well-known types sparingly; ids are strings (UUIDv7). Document every field with comments — the schema is the protocol documentation.",
       "Error semantics (map to Connect codes): head moved → `FAILED_PRECONDITION`; `path_key` collision → `ALREADY_EXISTS`; not a member → `NOT_FOUND` (do not leak existence); viewer writing → `PERMISSION_DENIED`.",
       "Configure `buf breaking` against `master` in `make lint` once the first version is merged."],
      ["Implementing any handler.", "Sharing/invitation RPCs (Phase 3) and key-management RPCs (Phase 4) — but leave room for them."])

issue("store", 1, "feat(store): PostgreSQL schema, migrations, and integration test stack", ["area:server"],
      "Create the PostgreSQL data model from SPEC.md §5 with embedded forward-only migrations, plus the `docker compose` stack (PostgreSQL + an S3-compatible store) behind `make test-integration`.",
      ["**Given** an empty database, **when** the server's migration step runs, **then** all tables from SPEC.md §5 (except Phase 4/5 tables, which may be created later) exist with their constraints.",
       "**Given** two server processes starting concurrently against the same database, **when** both run migrations, **then** migrations apply exactly once (advisory lock) and both start.",
       "**Given** a migrated database, **when** migrations run again, **then** nothing changes.",
       "**Given** two live documents in one vault, **when** they would share a `path_key`, **then** the database rejects the second (unique partial index on live documents).",
       "**Given** `make test-integration`, **when** run on a machine with Docker, **then** it brings up PostgreSQL and the S3-compatible store, runs `//go:build integration` tests, and tears everything down even on failure."],
      ["`pgx/v5` with a pool. Migrations embedded via `embed.FS`; a small in-house runner or `golang-migrate`/`goose` — decide and note it in the PR.",
       "PostgreSQL client certificates rotate in production: the connection config must re-read cert files for new connections (SPEC.md §3). Test with a cert swap if practical.",
       "S3 dev store: MinIO no longer publishes images; use e.g. Garage, SeaweedFS, or versitygw. Pin by digest.",
       "Integration tests skip (not fail) when Docker is unavailable, with a clear skip message."],
      ["Any RPC handler logic.", "Retention/purge jobs (Phase 2)."])

issue("server-skel", 1, "feat(server): HTTP server skeleton, configuration, logging, health and metrics", ["area:server"],
      "Turn `cmd/vault-sync-server` into a real server: env-based config, JSON logging, ConnectRPC mux, health/readiness and Prometheus metrics endpoints, CORS for Obsidian origins, request bounds, graceful shutdown.",
      ["**Given** required env vars are missing or invalid, **when** the server starts, **then** it exits non-zero with a message naming each problem.",
       "**Given** a running server, **when** `/healthz` is requested, **then** it returns 200; **when** `/readyz` is requested while the database is unreachable, **then** it returns 503.",
       "**Given** a running server, **when** the metrics port is scraped, **then** Go runtime and per-RPC request metrics are exposed, and the metrics port is separate from the API port.",
       "**Given** a request with `Origin: app://obsidian.md` (and `capacitor://localhost`, `http://localhost`), **when** it is a CORS preflight, **then** it is allowed; **given** any other origin, **then** it is not.",
       "**Given** a request body larger than the configured maximum, **then** it is rejected before being buffered in full.",
       "**Given** SIGTERM, **then** the server stops accepting new requests and drains in-flight ones within the configured timeout.",
       "**Given** `GetServerInfo`, **then** it returns the build version and protocol version without authentication."],
      ["Document every env var in `docs/configuration.md`.", "`log/slog` JSON handler; never log request bodies, tokens, or paths.", "Keep `main.go` thin; put wiring in `internal/server`."],
      ["Authentication (separate issue)."], deps=["proto"])

issue("auth", 1, "feat(auth): OIDC bearer authentication, JIT users, device registration", ["area:server", "security"],
      "Authenticate every non-public RPC and WebSocket upgrade with an OIDC access token (JWT) validated against the issuer's JWKS; create users on first sight; let a user register devices (SPEC.md §9.1).",
      ["**Given** a valid token, **when** an authenticated RPC is called, **then** it succeeds and the user exists in `users` keyed by `(issuer, subject)`.",
       "**Given** a token that is expired, has the wrong `iss` or `aud`, an unknown `kid`, `alg: none`, or an HMAC algorithm, **then** the request is rejected with `UNAUTHENTICATED`.",
       "**Given** a token signed with a key that appears in the JWKS after rotation, **then** the server refreshes the JWKS and accepts it; **given** a flood of unknown `kid`s, **then** JWKS refreshes are rate-limited.",
       "**Given** an authenticated user, **when** they register a device with a name and X25519 public key, **then** the device is listed for that user only.",
       "**Given** tests, **then** they use a local fake OIDC issuer (no external network)."],
      ["`github.com/coreos/go-oidc/v3` or equivalent; allowed algorithms are an explicit allow-list (RS256, ES256, EdDSA).",
       "Issuer URL and audience come from config. The plugin will obtain tokens via the Device Authorization Grant (Phase 2) — the server only validates.",
       "Put the auth interceptor in one place so new RPCs cannot forget it; a test enumerates all registered procedures and asserts each is either authenticated or on an explicit public allow-list."],
      ["Login flow in the plugin.", "Admin roles."], deps=["store", "server-skel"])

issue("authz", 1, "feat(authz): vault membership enforcement and vault RPCs", ["area:server", "security"],
      "Implement vault creation/listing and a single authorization layer that resolves `(user, vault)` to a role for every vault-scoped RPC (SPEC.md §9.2).",
      ["**Given** a user, **when** they create a vault, **then** they are its `owner` and it appears in their vault list but not in any other user's.",
       "**Given** a non-member, **when** they call any vault-scoped RPC with that vault's id, **then** they receive `NOT_FOUND` and no data or timing difference reveals whether the vault exists beyond normal noise.",
       "**Given** a `viewer`, **when** they call a write RPC, **then** they receive `PERMISSION_DENIED`; read RPCs succeed.",
       "**Given** any vault-scoped RPC in the API, **then** a table-driven test exercises it as owner, editor, viewer, and non-member.",
       "**Given** ids from another vault (document, revision, blob) passed with a vault the caller is a member of, **then** the request fails (no cross-vault access)."],
      ["Membership management RPCs (invite/remove/change role) are Phase 3; seed memberships directly in tests.",
       "Every store query takes `vault_id`; prefer making cross-vault access unrepresentable in the store API."],
      ["Sharing UI or invitations."], deps=["auth", "proto"])

issue("blobs", 1, "feat(blobstore): chunked, resumable, content-addressed blob uploads", ["area:server"],
      "Store file contents in S3 with a chunked upload protocol that fits under the WAF's 1 MiB inspected-body limit, is idempotent, resumable, and verified (SPEC.md §5, §6.2).",
      ["**Given** a blob larger than the chunk size, **when** a client begins an upload, sends chunks, and commits, **then** the blob is stored at `vaults/{vault_id}/blobs/{blob_id}` and is downloadable byte-identical, including by range.",
       "**Given** a plaintext vault, **when** the committed bytes do not hash to the declared `blob_id`, **then** commit fails and nothing becomes visible.",
       "**Given** a blob that already exists, **when** a client begins the same upload, **then** the server reports it complete without transferring bytes.",
       "**Given** an upload interrupted after some chunks, **when** the client resumes, **then** it can learn which ranges are stored and send only the rest.",
       "**Given** a chunk larger than the configured maximum, or a total size above the per-blob limit, **then** it is rejected.",
       "**Given** an upload session abandoned past its TTL, **then** a cleanup routine removes its parts (and aborts S3 multipart uploads — they are otherwise invisible and leak).",
       "**Given** a viewer or non-member, **then** uploads are rejected per the authz rules."],
      ["Default chunk size 768 KiB (configurable). Use S3 multipart or staged part objects — note the choice; S3 multipart minimum part size is 5 MiB except the last part, so staged objects + server-side compose may be required.",
       "S3 credentials and endpoint from config; credentials re-read on change.", "AWS SDK for Go v2."],
      ["Blob garbage collection after revision purge (Phase 2)."], deps=["authz", "store"])

issue("revisions", 1, "feat(server): revisions, optimistic concurrency, and change feed", ["area:server"],
      "Implement the core of the protocol: committing revisions against a base, path uniqueness, tombstones, the vault-wide sequence, and the paginated change feed (SPEC.md §5, §6.1–§6.3).",
      ["**Given** a document whose head is R1, **when** two clients concurrently commit with base R1, **then** exactly one succeeds and the other receives `FAILED_PRECONDITION` with the current head.",
       "**Given** successful commits, **then** each gets a `seq` that is strictly increasing and gapless per vault, and `ListChanges(since)` returns exactly the revisions after `since`, in order, paginated with a server-capped limit.",
       "**Given** a new document whose normalized path (NFC + case-fold) equals a live document's, **then** commit fails with `ALREADY_EXISTS`; **given** `Café.md` (NFD) and `café.md` (NFC), **then** they collide.",
       "**Given** a delete, **then** it is a tombstone revision; the prior content remains retrievable via history; the path becomes free for a new document.",
       "**Given** a rename, **then** the document id is unchanged and only the path changes.",
       "**Given** a commit referencing a blob that is not complete in the same vault, **then** it fails.",
       "**Given** a commit retried after a lost response (same client-generated revision id), **then** it is idempotent: the same revision is returned, not a duplicate."],
      ["Client-generated revision ids (UUIDv7) make retries idempotent — required by the simulation's drop-response fault.",
       "Assign `seq` by `UPDATE vaults SET head_seq = head_seq + 1 ... RETURNING` in the commit transaction.",
       "`path_key` normalization lives in one Go function with a table test of tricky cases (NFD/NFC, Turkish dotless i, German ß, full-width chars); the TS client will mirror it with shared vectors in `testdata/paths/`."],
      ["Merging (clients do it).", "Retention."], deps=["blobs"])

issue("realtime", 1, "feat(realtime): authenticated WebSocket change notifications", ["area:server", "security"],
      "Add the realtime channel: an authenticated WebSocket per device that subscribes to vaults and receives `vault_changed{seq}` after commits (SPEC.md §6.4).",
      ["**Given** a subscribed client, **when** another client commits to the vault, **then** the subscriber receives `vault_changed` with the new `seq` within one second (local test).",
       "**Given** an upgrade request without a valid token or with a disallowed `Origin`, **then** the upgrade is refused.",
       "**Given** a subscription request for a vault the user is not a member of, **then** it is refused with an error frame and no notifications for that vault are ever sent.",
       "**Given** a member removed from a vault (simulate in the store), **then** their existing subscription stops receiving notifications.",
       "**Given** a slow client that does not read, **then** the server bounds its buffer and disconnects it rather than growing memory; frame size and message rate are capped.",
       "**Given** multiple server replicas, **then** notifications fan out across replicas (PostgreSQL `LISTEN/NOTIFY` or equivalent)."],
      ["`github.com/coder/websocket` (formerly nhooyr) is a good fit.", "Frames are the protobuf envelope from the proto issue.", "Correctness must never depend on notifications; they are a latency optimization."],
      ["Yjs frames (Phase 5)."], deps=["revisions"])

issue("engine-skel", 1, "feat(engine): sync-core skeleton with VaultAdapter and in-memory vault", ["area:plugin"],
      "Create the platform-independent engine package in `plugin/src/core` with the interfaces later issues fill in: `VaultAdapter`, an in-memory vault implementation, a typed protocol client over ConnectRPC, a journal interface with an in-memory implementation, and path normalization shared with the server.",
      ["**Given** `src/core`, **when** any file imports `obsidian` or `src/obsidian`, **then** `make lint` fails.",
       "**Given** the in-memory vault, **then** it implements `VaultAdapter` (list, read, write, rename, delete, stat, change events) and passes a shared adapter conformance test suite that the Obsidian adapter will also run later.",
       "**Given** the protocol client, **when** pointed at a locally running server, **then** it can call `GetServerInfo` and an authenticated RPC with a supplied token (integration test).",
       "**Given** the shared path vectors in `testdata/paths/`, **then** the TypeScript normalization produces exactly the same `path_key` as the Go implementation for every vector."],
      ["Use `@connectrpc/connect-web` transport; the transport must be injectable so the simulation can wrap it with fault injection.",
       "Content hashing via `@noble/hashes` (SHA-256), not Node `crypto`, so it runs on Android WebView."],
      ["Actual sync algorithms (Phase 2)."], deps=["proto"])

issue("sim", 1, "feat(sim): simulation harness with fault injection and server invariants", ["area:sim"],
      "Build the seeded multi-client simulation harness in `sim/` (SPEC.md §13) and use it in Phase 1 to prove server-side invariants with scripted protocol clients. Phase 2 plugs the real engine in.",
      ["**Given** `make test-sim SIM_SEEDS=N SIM_STEPS=M`, **then** it starts PostgreSQL, the S3 store, and a real `vault-sync-server`, runs N seeded schedules of M steps with K clients, and exits non-zero on any invariant violation, printing the seed.",
       "**Given** a seed, **when** re-run, **then** the client-side operation and fault schedule is identical.",
       "**Given** the fault injector, **then** it can drop a request, drop a response after the server applied it, delay, reorder, partition a client, and crash a client (discarding its in-memory state).",
       "**Given** scripted clients that commit with optimistic concurrency and retry, **then** the invariants hold: no acknowledged revision is missing from history; `seq` is gapless and monotonic; no two live documents share a `path_key`; no commit succeeded against a stale base.",
       "**Given** a deliberately broken server build (e.g. a test flag that skips the base-revision check), **then** the harness detects the violation within the default CI run (proves the harness has teeth).",
       "**Given** CI, **then** a short run (a few seeds) executes on every PR in under 5 minutes."],
      ["TypeScript, sharing the protocol client from `plugin/src/core`. Real server process — do not fake the server.",
       "Failing seeds are minimized (shrink steps) and committed as regression cases under `sim/regressions/`."],
      ["Engine-level invariants such as file convergence (Phase 2)."], deps=["revisions", "engine-skel"])

# ---------------------------------------------------------------- Phase 2
issue("pull", 2, "feat(engine): pull and apply remote changes without overwriting local edits", ["area:plugin"],
      "Implement the pull side of the engine: consume the change feed from a durable cursor, fetch content, and apply it to the vault, never overwriting unsynced local edits (SPEC.md §6.1, §8).",
      ["**Given** remote revisions after the cursor, **when** the engine pulls, **then** the local vault matches the remote heads and the cursor advances only after each change is durably applied.",
       "**Given** a local file edited since its last sync, **when** a remote revision for it arrives, **then** the local edit is not overwritten (it is handed to the merge path).",
       "**Given** the engine crashes mid-apply, **when** it restarts, **then** it resumes from the journal and reaches the same final state.",
       "**Given** engine-originated writes, **then** the resulting vault change events are not treated as user edits (echo suppression)."],
      ["Change detection by content hash, never mtime.", "Uses the journal interface; the IndexedDB implementation is a separate issue."],
      ["Merge algorithm (separate issue)."], deps=["sim"])

issue("push", 2, "feat(engine): push local changes with resumable uploads and concurrency retry", ["area:plugin"],
      "Implement the push side: detect local changes, upload content in chunks, commit against the known base, and on a moved head pull + merge + retry (SPEC.md §6.2).",
      ["**Given** a local create/edit, **when** the engine pushes, **then** the server head matches the local content and the journal marks it synced only after the commit is acknowledged.",
       "**Given** the commit response is lost, **when** the engine retries, **then** no duplicate revision is created.",
       "**Given** the head moved, **then** the engine pulls the new head, merges, and commits again with the new base.",
       "**Given** an interrupted upload, **when** the engine restarts, **then** it resumes without re-sending stored chunks."],
      ["Debounce rapid successive edits (configurable); never lose the last edit in a burst."],
      ["Merge algorithm details."], deps=["pull"])

issue("merge", 2, "feat(engine): three-way text merge and conflict copies", ["area:plugin"],
      "Implement SPEC.md §7: 3-way merge for text documents, conflict copies for overlapping edits and for binary documents, and a conflict log.",
      ["**Given** non-overlapping concurrent edits to a Markdown note, **then** both edits are present after sync on every client and no conflict copy is created.",
       "**Given** overlapping concurrent edits, **then** the remote version is in place, the local version exists as `<name> (conflict <device> <date>).<ext>`, and no conflict markers are inserted into the note.",
       "**Given** concurrent edits to a binary file, **then** remote wins in place and the local version is a conflict copy.",
       "**Given** any conflict, **then** it is recorded in the conflict log the UI will read.",
       "**Given** CRLF vs LF and a trailing-newline difference, **then** merges do not produce spurious conflicts."],
      ["A well-tested diff3 implementation (e.g. `node-diff3`) or `diff-match-patch` — justify the choice in the PR.", "Classification by extension is configurable."],
      ["JSON-aware merge for `.canvas`."], deps=["push"])

issue("structure-ops", 2, "feat(engine): renames, deletes, create collisions, delete-vs-edit", ["area:plugin"],
      "Handle structural operations per SPEC.md §6.3 so that structure changes are never lost or duplicated.",
      ["**Given** a rename on one client and an edit on another, **then** after sync the document has the new name and the edited content everywhere.",
       "**Given** a delete on one client and an edit on another, **then** the edit wins (the document exists with the edited content) everywhere.",
       "**Given** two clients create the same path offline, **then** after sync both files exist, one renamed as a conflict copy.",
       "**Given** a folder rename with many files, **then** it syncs as renames (no delete + re-upload of content).",
       "**Given** a rename chain A→B, B→C across clients, **then** no file is lost or duplicated."],
      ["Obsidian reports folder renames as per-file renames; the adapter conformance suite covers both."],
      [], deps=["merge"])

issue("paths", 2, "feat(engine): platform path rules and unmaterializable documents", ["area:plugin"],
      "Make the engine safe across Windows, macOS, Android, and Linux path rules (SPEC.md §8).",
      ["**Given** a remote document named `CON.md`, `a:b.md`, `trailing.`, or with a path over the platform limit, **when** synced to Windows rules, **then** it is tracked as unmaterializable, surfaced to the UI, and never silently dropped or renamed on the server.",
       "**Given** a later remote rename to a legal name, **then** the document materializes.",
       "**Given** two remote documents differing only in case, **then** this cannot happen (server rejects) — and a test proves the client's normalization matches the server's on the shared vectors."],
      ["The in-memory vault gets a configurable path-rules mode (posix, windows, macos) so the simulation covers it."], [], deps=["structure-ops"])

issue("journal", 2, "feat(engine): IndexedDB journal with crash safety", ["area:plugin"],
      "Implement the durable journal on IndexedDB (desktop + Android WebView) behind the journal interface.",
      ["**Given** the journal conformance suite, **then** the IndexedDB implementation passes it (run under `fake-indexeddb` in vitest).",
       "**Given** a simulated crash between any two journal writes, **then** recovery yields a consistent state (property test).",
       "**Given** two vaults open in one Obsidian install, **then** their journals are isolated.",
       "**Given** a schema upgrade of the journal, **then** existing data migrates without forcing a full resync."],
      [], ["Encrypting the journal at rest."], deps=["engine-skel"])

issue("sim-engine", 2, "feat(sim): engine-level convergence and no-lost-write invariants", ["area:sim"],
      "Plug the real engine into the simulation harness and check user-visible invariants under faults; run a long simulation nightly.",
      ["**Given** K engines making random edits, renames, deletes, and creates with faults, **when** the schedule ends and faults heal, **then** all vaults converge to identical content and structure.",
       "**Given** any edit that the engine reported as acknowledged, **then** its content is present in the final vault, in history, or in a conflict copy.",
       "**Given** no delete was performed on a path, **then** no file disappears.",
       "**Given** vaults with Windows path rules among the clients, **then** invariants hold modulo the unmaterializable set.",
       "**Given** a nightly job, **then** it runs a long simulation (many seeds/steps) and files an issue with the seed on failure."],
      ["The nightly job is a GitHub Actions scheduled workflow — workflow-file changes need a token with the `workflow` scope; if pushing it fails, label the issue `needs-human` with the file ready on a branch."],
      [], deps=["structure-ops", "paths", "journal"])

issue("adapter", 2, "feat(plugin): Obsidian vault adapter and editor-safe writes", ["area:plugin"],
      "Implement `VaultAdapter` on Obsidian's API: map vault events into the engine, and write remote changes safely even when the file is open in an editor.",
      ["**Given** the adapter conformance suite, **then** the Obsidian adapter passes it inside real Obsidian (e2e harness).",
       "**Given** a file open in the editor with the cursor mid-document, **when** a non-overlapping remote change is applied, **then** the user's cursor position and unsaved keystrokes are preserved.",
       "**Given** Obsidian startup indexing, **then** the initial `create` storm is not mistaken for user edits.",
       "**Given** the plugin is disabled and re-enabled, **then** it resumes without a full resync."],
      ["Use `vault.process`/editor transactions for open files; `vault.adapter` only where the Vault API lacks a capability (hidden files)."],
      ["`.obsidian/` config sync (separate issue)."], deps=["pull", "e2e"])

issue("login-ui", 2, "feat(plugin): device-flow login, settings, status bar, vault selection", ["area:plugin"],
      "Give the plugin a usable UI: sign in with the OAuth Device Authorization Grant, choose or create a remote vault, see sync status.",
      ["**Given** a server URL, **when** the user clicks sign in, **then** the plugin shows the verification URL and user code, polls, and stores the refresh token in plugin data on success.",
       "**Given** an expired access token, **then** it refreshes transparently; **given** a revoked refresh token, **then** the user is prompted to sign in again and no local changes are lost meanwhile.",
       "**Given** a signed-in user, **then** they can create a vault or connect this local vault to an existing remote vault, with a clear warning when connecting a non-empty local vault to a non-empty remote one.",
       "**Given** sync activity, **then** the status bar shows idle / syncing / offline / error / conflicts with counts."],
      ["Works identically on desktop and Android.", "Server URL, OIDC issuer, and client id are discovered from `GetServerInfo` where possible to minimize settings."],
      [], deps=["adapter"])

issue("history", 2, "feat: history browsing, restore, and retention", ["area:server", "area:plugin"],
      "Let users browse a document's history and restore any revision; implement the server-side retention policy and blob garbage collection (SPEC.md §11).",
      ["**Given** a document, **when** the user opens its history, **then** they see revisions with time and device, can preview any, and restoring creates a new head revision.",
       "**Given** a deleted file, **then** the user can find and restore it.",
       "**Given** the retention policy, **then** only non-head revisions and tombstones older than the policy are purged, and a test proves heads are never purged.",
       "**Given** a purged revision was the last reference to a blob, **then** the blob is deleted after the grace period and not before."],
      [], ["Per-user retention settings UI."], deps=["structure-ops"])

issue("conflict-ui", 2, "feat(plugin): conflict view", ["area:plugin"],
      "Surface conflicts and unmaterializable documents so the user can resolve them.",
      ["**Given** conflicts in the log, **then** a view lists them with links to both versions and a one-click side-by-side comparison.",
       "**Given** the user resolves a conflict by deleting the conflict copy, **then** the entry clears.",
       "**Given** unmaterializable documents, **then** they are listed with the reason and the remote path."],
      [], [], deps=["merge", "login-ui"])

issue("config-sync", 2, "feat(plugin): opt-in .obsidian config sync", ["area:plugin"],
      "Sync selected parts of the vault's config folder per SPEC.md §8.",
      ["**Given** config sync disabled (default), **then** nothing under the config folder syncs.",
       "**Given** categories enabled (themes, snippets, hotkeys, enabled-plugin list, plugin code+data), **then** only those paths sync, honoring a custom config folder name.",
       "**Given** any setting, **then** `workspace*.json` and this plugin's own data never sync.",
       "**Given** a synced plugin list change, **then** the user is told a reload is needed rather than the plugin reloading Obsidian silently."],
      [], [], deps=["adapter"])

issue("export", 2, "feat(export): plaintext vault export for tape archival", ["area:server"],
      "Add `vault-sync-server export`: write every vault's head state to a directory tree for the operator's tape archival tooling (replaces livesync-bridge).",
      ["**Given** vaults on the server, **when** export runs, **then** `<out>/<vault name or id>/...` mirrors each vault's live head documents byte-for-byte.",
       "**Given** an export interrupted midway, **then** the previous complete export is untouched (write to a staging dir, then atomically swap).",
       "**Given** a document path containing `..`, absolute paths, or other traversal attempts, **then** export refuses to write outside the vault directory.",
       "**Given** a run, **then** it emits a JSON summary (vaults, files, bytes, duration) and a metric/exit code that alerting can use."],
      ["Runs as a separate Deployment/CronJob with its own read-only DB role and S3 credentials (Phase 4 adds the escrow key)."],
      ["Encrypted vaults (Phase 4)."], deps=["revisions"])

issue("e2e", 2, "test(e2e): plugin e2e harness in real Obsidian", ["area:plugin"],
      "Set up `wdio-obsidian-service` so `make test-e2e` runs the plugin inside real Obsidian against a real server, headless in the VM, and on Windows + macOS in CI.",
      ["**Given** `make test-e2e` in the dev VM, **then** it downloads a pinned Obsidian version, runs headless under xvfb against a local server, and passes a smoke test (plugin loads, signs in with a test token, syncs one file between two vaults).",
       "**Given** CI, **then** the same suite runs on `ubuntu-latest`, `windows-latest`, and `macos-latest`, plus once in emulated-mobile mode.",
       "**Given** the adapter conformance suite, **then** it runs inside Obsidian through this harness."],
      ["CI workflow changes need a token with `workflow` scope; if the push is refused, label `needs-human` with the branch ready.", "Pin the Obsidian version; Renovate can bump it."],
      ["Real Android device automation."], deps=["engine-skel"])

issue("release", 2, "chore(release): server image, Helm chart, plugin release", ["area:ops"],
      "Package everything for deployment, mirroring tape-archiver: Nix-built OCI image, an app-template Helm chart, and plugin GitHub releases installable with BRAT.",
      ["**Given** `make build-images`, **then** a Nix `streamLayeredImage` OCI image with the server binary is built and loaded; `PUSH_ALL=true` pushes to `ghcr.io/soliddowant/vault-sync`.",
       "**Given** `make chart-lint`, **then** the chart lints and renders the server Deployment, the export CronJob, a metrics ServiceMonitor, and Secrets references for DB certs, S3, and (later) escrow — with the escrow Secret never mounted into the server.",
       "**Given** `make release VERSION=x.y.z` (dry-run by default), **then** it tags, and the GitHub release carries `main.js`, `manifest.json`, and `styles.css` so BRAT can install it.",
       "**Given** `docs/deployment.md`, **then** it covers PostgreSQL (CNPG, client certs), S3 (RGW), Authentik (device-flow application), the WAF body limit, and the export job."],
      [], ["Deploying to the cluster (human)."], deps=["export", "login-ui"])

issue("android-checklist", 2, "docs(testing): Android manual test checklist", ["area:plugin"],
      "Write `docs/testing/android.md`: the manual checks a human runs on a physical Android device before a release, until Android e2e is automated.",
      ["**Given** the checklist, **then** it covers install via BRAT, sign-in, initial sync of a large vault, offline edits, app killed mid-sync, background/foreground transitions, conflicts, attachments, and battery/network behavior, each with expected results."],
      [], ["Automating Android."], deps=["login-ui"])

issue("dogfood", 2, "chore: deploy to the homelab for dogfooding", ["area:ops", "needs-human"],
      "Deploy the Phase 2 build to the operator's cluster and run it alongside the existing setup. This needs the human: cluster access, Authentik application, DNS/gateway, WAF rules.",
      ["**Given** the release artifacts and `docs/deployment.md`, **when** the human deploys, **then** two devices (desktop + Android) sync a test vault for a week with the nightly export landing in the archival path.",
       "**Given** issues found while dogfooding, **then** they are filed as bugs with reproduction steps."],
      ["Agents prepare everything up to the deployment; they do not touch the cluster."], [], deps=["release", "android-checklist"])

# ---------------------------------------------------------------- Phase 3
issue("membership-api", 3, "feat(server): vault membership management and invitations", ["area:server", "security"],
      "Let owners invite users, change roles, and remove members; let invited users accept (SPEC.md §9.2).",
      ["**Given** an owner, **when** they create an invitation with a role, **then** a single-use, expiring invite code is returned; **when** another authenticated user redeems it, **then** they become a member with that role.",
       "**Given** an expired, revoked, or already-used code, **then** redemption fails without revealing the vault.",
       "**Given** an owner changes a role or removes a member, **then** it takes effect on the next request and on open realtime subscriptions.",
       "**Given** a vault, **then** it always has at least one owner (the last owner cannot leave or be demoted).",
       "**Given** non-owners, **then** every membership RPC is rejected (table-driven authz test)."],
      ["Invite codes are high-entropy and stored hashed."], ["Email delivery of invites."])

issue("sharing-ui", 3, "feat(plugin): sharing UI and joining shared vaults", ["area:plugin"],
      "Plugin UI to manage members and invitations and to join a shared vault by invite code.",
      ["**Given** an owner, **then** they can list members, invite, change roles, and remove members from the settings UI.",
       "**Given** an invite code, **then** a user can join the vault and choose a local folder/vault to sync it into.",
       "**Given** a viewer, **then** local edits are not pushed, the user is clearly told the vault is read-only, and their local edits are preserved as local-only files rather than discarded."],
      [], [], deps=["membership-api"])

issue("sim-multiuser", 3, "test(sim): multi-user scenarios and permission changes under faults", ["area:sim", "security"],
      "Extend the simulation with multiple users, roles, and membership changes mid-schedule.",
      ["**Given** a member demoted to viewer or removed mid-schedule, **then** none of their later commits are accepted and all acknowledged earlier commits remain.",
       "**Given** a removed member, **then** they stop receiving changes after removal.",
       "**Given** all other invariants, **then** they still hold."],
      [], [], deps=["membership-api"])

# ---------------------------------------------------------------- Phase 4
issue("crypto-core", 4, "feat(crypto): primitives, suite versioning, cross-language vectors", ["area:crypto", "security"],
      "Implement the SPEC.md §9.3 primitives in TypeScript and Go with a versioned ciphertext format and shared test vectors.",
      ["**Given** `testdata/crypto/`, **then** both implementations pass every vector: HKDF sub-key derivation, XChaCha20-Poly1305 seal/open with AAD, X25519 sealed-box wrap/unwrap, HMAC path_key/blob_id, Argon2id passphrase wrapping.",
       "**Given** a ciphertext with an unknown suite version, a modified AAD, or a truncated tag, **then** decryption fails closed.",
       "**Given** nonce generation, **then** it uses a CSPRNG and a test detects reuse across a large sample."],
      ["`@noble/*` in TS; `golang.org/x/crypto` in Go. Argon2id parameters must be tolerable on low-end Android — measure and record."],
      ["Key management flows."])

issue("user-keys", 4, "feat(keys): user key pairs, recovery passphrase, device unlock", ["area:crypto", "area:plugin", "area:server"],
      "Create per-user X25519 key pairs wrapped by a recovery passphrase, stored server-side; devices unlock and cache them.",
      ["**Given** a new user enabling E2EE, **then** a key pair is created on the device and the private key is uploaded only in passphrase-wrapped form.",
       "**Given** a second device, **when** the user enters the passphrase, **then** it unlocks the same key; a wrong passphrase fails without lockout bypass (rate-limited server-side).",
       "**Given** server and database contents only, **then** the private key cannot be recovered without the passphrase (documented threat model + test that nothing unwrapped is persisted)."],
      [], ["Device-to-device linking.", "Shamir recovery."], deps=["crypto-core"])

issue("vault-keys", 4, "feat(keys): vault key epochs, key slots, rotation on member removal", ["area:crypto", "area:server", "area:plugin"],
      "Envelope encryption for vaults: epoch keys wrapped per member (and escrow), rotation when a member is removed.",
      ["**Given** an E2EE vault, **then** each member has a key slot for every epoch they are entitled to, and the server stores only wrapped keys.",
       "**Given** a member is removed, **then** a new epoch is created by an owner client, wrapped for remaining members (and escrow), and subsequent revisions use it.",
       "**Given** a member is added, **then** they receive slots for the current epoch (and past epochs per policy, decided and logged).",
       "**Given** concurrent rotations, **then** exactly one epoch wins (server-side compare-and-set)."],
      [], [], deps=["user-keys", "membership-api"])

issue("e2ee-engine", 4, "feat(engine): encrypt content and paths in E2EE vaults", ["area:crypto", "area:plugin"],
      "Make the engine encrypt everything the server stores for E2EE vaults while keeping all sync invariants.",
      ["**Given** an E2EE vault, **then** the server database and object store contain no plaintext content or paths (test greps a populated DB dump and bucket for known plaintext markers).",
       "**Given** encrypted paths, **then** path collisions are still prevented via HMAC `path_key`.",
       "**Given** the simulation run in E2EE mode, **then** all Phase 2 invariants hold.",
       "**Given** content dedup, **then** blob ids are HMACs and clients verify them after decryption."],
      [], ["Converting an existing plaintext vault to E2EE (follow-up)."], deps=["vault-keys"])

issue("escrow", 4, "feat(export): escrow recipient and decrypting export", ["area:crypto", "area:server", "area:ops"],
      "Support opt-in escrow per vault (SPEC.md §9.4) and decrypt escrow vaults in the export job.",
      ["**Given** an escrow-enabled vault, **then** every epoch key is also wrapped to the deployment's escrow public key, which clients fetch from `GetServerInfo` and pin per vault at creation.",
       "**Given** the export job with the escrow private key, **then** it exports escrow vaults as plaintext identical to a plaintext vault's export.",
       "**Given** the API server's configuration and Helm values, **then** the escrow private key is not readable by the server (chart test).",
       "**Given** an E2EE vault without escrow, **then** export skips it and reports that it did."],
      ["Optional follow-up: `vault-sync-server escrow split/combine` using Shamir secret sharing for offline recovery of the escrow key."],
      [], deps=["e2ee-engine", "export"])

issue("e2ee-ui", 4, "feat(plugin): E2EE setup, escrow disclosure, recovery UX", ["area:plugin", "area:crypto"],
      "UI for creating E2EE vaults, choosing escrow, setting and entering the recovery passphrase.",
      ["**Given** vault creation, **then** the user chooses plaintext / E2EE / E2EE with escrow, with a plain-language explanation of who can read the data in each case.",
       "**Given** an E2EE vault, **then** the vault's encryption mode and escrow status are always visible in settings.",
       "**Given** a lost passphrase and no other unlocked device, **then** the UI explains what is and is not recoverable."],
      [], [], deps=["e2ee-engine"])

issue("crypto-review", 4, "security: independent crypto review", ["area:crypto", "security"],
      "Before Phase 4 closes, an independent review of the whole crypto design and implementation (in addition to the regular phase-end bug hunt).",
      ["**Given** the review, **then** findings are filed as `security` issues with severity, and critical/high ones are fixed before the phase closes.",
       "**Given** the review, **then** `docs/security/threat-model.md` documents what each party (server, DB, object store, export job, other members, removed members) can learn or do."],
      [], [], deps=["escrow", "e2ee-ui"])

# ---------------------------------------------------------------- Phase 5
issue("yjs-design", 5, "docs(yjs): choose compaction runtime and finalize CRDT design", ["area:server", "question"],
      "Resolve SPEC.md §10's open question (where Yjs compaction runs — Go port, Node sidecar, or clients only) and finalize the Phase 5 protocol details before implementation.",
      ["**Given** the decision, **then** `SPEC.md` §10 is updated with the chosen runtime, snapshot format, compaction triggers, and E2EE handling, with the alternatives and reasoning recorded on the decision log."],
      ["Evaluate Go Yjs ports for compatibility with `yjs` update encoding v1/v2 using real update logs."], ["Implementation."])

issue("yjs-server", 5, "feat(realtime): Yjs update log, relay, and awareness", ["area:server", "security"],
      "Store and relay Yjs updates per document and relay awareness over the realtime channel.",
      ["**Given** a `yjs` document, **when** a client sends an update, **then** it is appended to the log, relayed to other subscribers, and acknowledged; a client reconnecting with a state vector receives exactly what it is missing.",
       "**Given** a viewer, **then** their updates are rejected; awareness is relayed only to members.",
       "**Given** update and awareness floods, **then** size and rate limits apply."],
      [], [], deps=["yjs-design"])

issue("yjs-conversion", 5, "feat: exactly-once text → yjs conversion", ["area:server", "area:plugin"],
      "Convert existing text documents to `yjs` exactly once using a server-granted lease and compare-and-set (SPEC.md §10).",
      ["**Given** two clients that try to convert the same document simultaneously, **then** exactly one initializes the Y.Doc and the content is never duplicated (simulation test).",
       "**Given** a converting client crashes, **then** the lease expires and another client can convert."],
      [], [], deps=["yjs-server"])

issue("yjs-editor", 5, "feat(plugin): CodeMirror binding and disk bridge for live editing", ["area:plugin"],
      "Bind Y.Text to Obsidian's editor and keep it consistent with the file on disk, including edits made outside the editor.",
      ["**Given** two users editing the same note, **then** both see each other's edits live and the documents converge.",
       "**Given** an edit from another plugin, `processFrontMatter`, or an external editor, **then** it is diffed into the Y.Text and propagates.",
       "**Given** the note is closed, **then** remote updates still reach the file on disk."],
      ["`y-codemirror.next`; Obsidian's CodeMirror 6 instance."], [], deps=["yjs-conversion"])

issue("yjs-awareness-ui", 5, "feat(plugin): presence and remote cursors", ["area:plugin"],
      "Show who else is in a note and their cursors/selections.",
      ["**Given** two users in a note, **then** each sees the other's name and cursor; awareness disappears within seconds of disconnect."],
      [], [], deps=["yjs-editor"])

issue("yjs-compaction", 5, "feat: Yjs snapshots and compaction", ["area:server", "area:plugin"],
      "Implement snapshotting/compaction per the Phase 5 design decision.",
      ["**Given** a long update log, **then** compaction produces a snapshot after which new clients load in bounded time, and no update is lost (simulation)."],
      [], [], deps=["yjs-server", "yjs-design"])

issue("yjs-e2ee", 5, "feat(crypto): encrypted Yjs updates", ["area:crypto", "area:plugin"],
      "Encrypt Yjs updates and snapshots in E2EE vaults; compaction per the design for escrow vs non-escrow vaults.",
      ["**Given** an E2EE vault, **then** the server stores and relays only ciphertext updates, and live editing still converges.",
       "**Given** an escrow vault, **then** the export job can produce the plaintext Markdown."],
      [], [], deps=["yjs-compaction", "e2ee-engine"])

issue("yjs-sim", 5, "test(sim): CRDT convergence under faults", ["area:sim"],
      "Extend the simulation to live-editing documents.",
      ["**Given** concurrent CRDT edits, conversions, disconnects, and compactions under faults, **then** all replicas converge and no character inserted by an acknowledged update is lost."],
      [], [], deps=["yjs-editor", "yjs-compaction"])
