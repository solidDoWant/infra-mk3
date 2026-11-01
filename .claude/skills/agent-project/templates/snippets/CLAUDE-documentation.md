## Documentation

Any change to a user-facing surface (env vars, settings, API, metrics, Helm values) updates the relevant doc in the same change. Keep `SPEC.md` current with any behavioural change it describes.

**Write for one audience at a time.** The docs have these readers, and each page is for one of them (adapt the list to the project):
- **Users:** people who use the product. They know the host application, not servers or cryptography.
- **Admins:** people who run the server. They know Kubernetes, the database, object storage and OIDC, and need concepts and settings, not internals.
- **Developers:** people who change the code. They need the design and the reasons for it.
- **Agents:** `docs/agents/`, `.claude/` and this file.

Put each fact in the page of the audience that acts on it, at that audience's depth. For example, a user needs to know that a forgotten passphrase can't be recovered. An admin needs to know that it is stretched with a slow hash (Argon2id), and what its cost means for weak devices. A developer needs the parameters and the library. Other audiences link to the page instead of repeating it. `docs/README.md` lists the audiences and the pages.

**Write only what the code doesn't already say.** Reference material that restates code is generated from the code and checked in CI: settings tables, metrics, Helm values, error lists. Facts only an agent changing the code needs go next to that code, in package docs, proto comments or test names. Don't duplicate the code in prose. History stays in git and the issues. Size is not a goal or a check: a page is the right length when every fact on it serves its reader once and is not stated elsewhere.

**Plain English for human readers.** Load the `simple-english` skill (`.claude/skills/simple-english/`, Plain mode) before you write or change text written mainly for people: anything under `docs/` except `docs/agents/`, `README.md`, `SPEC.md`, `CHANGELOG.md` and release notes, and status reports or questions for the owner. It doesn't apply to code comments, commit messages, issue bodies written for agents, or agent instructions.
