# Shared Tekton CI for agent projects

Status: proposed (2026-11-22). Owner decision: build this instead of copying CI scripts into each project (infra-mk3 #981, closed).

## Problem

Each agent project carries its own copy of the CI: githubgate has about 3,500 lines in `scripts/ci/` (40 files, half of them tests) plus about 500 generated lines in `.tekton/`. The copies drift:

- **The skill's templates fell behind.** They still held registrygate's early CI after githubgate fixed four release failures (0.6.0–0.6.3) and reworked CI speed.
- **Fixes don't spread.** registrygate's Tekton release still has the shape that failed for githubgate, and has never run.
- **Every project tests the same code.** Each one re-runs identical tests for identical scripts, and its agents can edit their copy.

## Goal

Every project's CI and release run on one shared implementation in infra-mk3. A project keeps only:

- three short PipelineRuns in `.tekton/` (pull request, push, release);
- a `ci.yaml` that says what its stages are and what a release publishes;
- the Makefile targets that `ci.yaml` names.

A fix to the CI lands once, in infra-mk3, is tested there, and reaches every project.

Not a goal: changing what CI checks or what a release publishes. The behaviour is githubgate's v0.7.1 CI, moved.

## Design

### Shared pieces (infra-mk3, `cluster/gitops/ci/tekton/`)

```
ci-tools/                  source of the ci-tools image (built and pushed by infra-mk3 CI)
  bin/ci-stages              runs the stages from ci.yaml in parallel (today's stages.sh,
                             cpuset-first.sh, stages-report.py, changes.py, changed-files.sh)
  bin/ci-trust               the stage trust bundle (ca-bundle.sh, stage-env.sh)
  bin/ci-github-check        the TLS check on the release's code path (github-api-check.py, github_https.py)
  bin/ci-release             publish images and charts, build assets, create the GitHub
                             release, upload assets (publish-release.sh, build-release-assets.sh,
                             upload-release-assets.py)
  bin/ci-cleanup             cache and disk housekeeping (cleanup.sh, trim-cache.sh,
                             df-percent.sh, stale-images.sh)
  bin/ci-report              per-stage check runs (today's inline report task script)
  bin/ci-test-guard          the test-removal guard (test-guard.py)
  tests/                     every tool's tests, and a fixture project (below)
  Dockerfile
pipelines/
  ci-pull-request.yaml       clone, ci, test-guard, report
  ci-push.yaml               clone, ci, report, cleanup
  ci-release.yaml            clone, publish (as ci-release, no shared workspace)
  ci-*-next.yaml             the same three, on the candidate ci-tools (see Rollout)
docker/task/task.yaml        gains a ci-tools image volume at /run/ci-tools
```

- **`ci-tools` is an OCI image**, mounted into the shared `docker` Task as an image volume. The Task already mounts `yq` that way. A ConfigMap can't be used: the Task's pods run in each project's namespace, not `ci-tekton`. The image is pinned by digest in the Pipelines, never by tag.
- **The Pipelines live in `ci-tekton`** and are fetched with the cluster resolver (`kind: pipeline`). `cluster-resolver-config` already allows only `ci-tekton`, so a project can't point CI at another namespace.
- **The ServiceAccounts stay as they are** (from the `ci/project` chart):
  - `ci-build` runs the stages;
  - `ci-report` runs the test guard and the report;
  - `ci-release` runs the release, only on the project's release refs (the admission policy).

  githubgate's interceptor gives each its GitHub access, and registrygate gives it its registry access, with no token in any pod.

### The project's side

`.tekton/pull-request.yaml` (push and release are the same shape):

```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: toolgate-pull-request-
  annotations:
    pipelinesascode.tekton.dev/on-cel-expression: >-
      event == "pull_request" && target_branch == "master" && body.action != "ready_for_review"
    pipelinesascode.tekton.dev/max-keep-runs: "10"
spec:
  pipelineRef:
    resolver: cluster
    params:
      - {name: kind, value: pipeline}
      - {name: name, value: ci-pull-request}
      - {name: namespace, value: ci-tekton}
  params:
    - {name: repo_url, value: "{{ repo_url }}"}
    - {name: revision, value: "{{ revision }}"}
    - {name: repo, value: "{{ repo_owner }}/{{ repo_name }}"}
    - {name: pull_request_number, value: "{{ pull_request_number }}"}
```

The PipelineRun keeps what has to be per project: the PaC trigger (`on-cel-expression`), the run name, and the PaC variables passed as params. Sizing, such as the dind sidecar's memory, comes from `ci.yaml`.

`ci.yaml` at the repository root:

```yaml
version: 1
# The CI image: built from flake.nix by ci-tools, as today's ci-image.sh does.
image:
  flake: .            # the dev shell the stages run in
# The dind sidecar's memory: max(8 GiB, 1.5 × the measured peak, which every run prints).
memory: 13Gi
stages:               # all run at once, each a container of the CI image
  lint:
    run: make lint
  unit:
    run: make test && make build
  generate:
    run: make check-generate
    own-tree: true    # gets its own copy of the checkout (it rewrites files)
  integration:
    run: make test-integration
  e2e:
    run: make test-e2e
    kind: true        # creates kind clusters with ci-kind-config; starts first
    images: make e2e-images   # built on the shared dockerd while the cluster comes up
  docs:
    run: make docs-check
# Optional: which changed paths a pull request needs which stages for. Without
# a match, every stage runs. A push runs every stage.
changes:
  docs: ["docs/**", "**/*.md"]
release:
  images:             # pushed through registrygate, both platforms, :latest for a final version
    - name: ghcr.io/soliddowant/toolgate
      build: make build-images PUSH=true
  charts: [deploy/charts/toolgate]
  binaries:           # static, linux/darwin × amd64/arm64, uploaded with checksums.txt
    - {package: ./cmd/toolgate, name: toolgate}
  crds: deploy/charts/toolgate/templates/crds   # all CRDs → crds.yaml on the release
  notes: CHANGELOG.md                           # the "## <version>" section
```

`ci-stages` validates `ci.yaml` against a schema and fails the run with the field at fault. A wrong `ci.yaml` breaks a pull request, never a release. That's because the release Pipeline's first step validates `release:`, and the PR pipeline runs the same check as a stage.

### Behaviour kept from githubgate v0.7.1

- **Stages:** they run in parallel in the dind VM, pinned to the run's CPU budget (`GOMAXPROCS` set). Each stage gets a check run on the commit, and a failure report goes in the check's text. The step log prints a table of stages (time, memory, CPU) and the VM's peak memory.
- **Pull requests** are tested merged with `master`, and `changes` picks the stages they need.
- **The release:**
  - one task as `ci-release`, with no shared workspace;
  - the trust bundle includes the interceptor's CA, and `NIX_SSL_CERT_FILE` points at the bundle;
  - the GitHub TLS check uses the same code path as the upload;
  - a pre-release for `-rc.N` and `:latest` only for a final version.
- **The push run** cleans the Docker cache that the promoter keeps.

### Testing the shared CI

- **Unit tests:** every `ci-tools` tool keeps its tests, run by infra-mk3's CI when `cluster/gitops/ci/tekton/ci-tools/**` changes.
- **A fixture project** (`ci-tools/tests/fixture/`), a tiny Go module with a chart, a CRD, a client binary and a `ci.yaml`. infra-mk3 CI runs `ci-stages` on it and a release dry run: assets built, checksums, notes, and every publish command printed but not run. This replaces the per-project `release-assets_test.sh` and `tekton-release_test.py`.

### Rollout of a ci-tools change (canary)

1. A merged change to `ci-tools/` builds a new image. The `ci-*-next` Pipelines move to its digest in the same PR.
2. **githubgate is the canary:** its `.tekton/` points at `ci-pull-request-next` and `ci-push-next`. Its next PR and push runs use the candidate.
3. After a green PR run and a green push run on githubgate, a second infra-mk3 PR moves the stable Pipelines to the same digest. Renovate-style digest bumps only ever touch `-next`.
4. Release-path changes also need githubgate's next release to go out as `-rc.1` on `ci-release-next` before the stable `ci-release` moves. This is the rc-first rule, applied to the shared release.

A bad `ci-tools` change can then break only githubgate's CI, and only until it's rolled back.

### What happens to the skill

`templates/scripts/ci/` goes away. Step 4's CI section becomes: add the three PipelineRuns and `ci.yaml` (an example of each in the skill), make the Makefile targets, and onboard the project with the `ci/project` chart as today. The release-path lessons stay in the skill as text.

## Migration order

1. **Build:**
   - `ci-tools` from githubgate v0.7.1's `scripts/ci/`, generalized to read `ci.yaml`;
   - the six Pipelines;
   - the fixture project and its tests in infra-mk3 CI;
   - the Task's image volume.
2. **githubgate:**
   - replace `scripts/ci/` and the generated `.tekton/` with `ci.yaml` and the short PipelineRuns;
   - compare a PR run and a push run against the last old runs (stages, time, check runs);
   - cut a patch release as `-rc.1`, then the final.
3. **registrygate (#251, #260):** adopt the shared CI, then make its first Tekton release, `v0.4.1-rc.1` and then the final, with its assets. Delete the GHA `release.yml`.
4. **toolgate, then harbor-operator:** onboard to Tekton (`ci/project` chart release), write their `ci.yaml`, check the runs, and cut an rc release. Then delete their GHA workflows.
5. **The skill:** replace `templates/scripts/ci/` as above.
6. **vault-sync, later:** it needs an extension for its Android emulator e2e (KVM), which the shared `docker` Task doesn't offer.

## Open questions

- **Where ci-tools is published:** Harbor (`harbor.<domain>/ci/ci-tools`, pulled through registrygate) or ghcr. Harbor keeps it private and in-cluster, so I propose Harbor.
- **The `ci.yaml` schema:** a JSON Schema in `ci-tools/`, and possibly published for editor validation.
- **Projects whose stages don't fit the `run:` + `kind:` shape:** they could use an escape hatch, a stage whose command is a repo script, but that runs repo code the same way `run:` already does. vault-sync's emulator is the only known case.
