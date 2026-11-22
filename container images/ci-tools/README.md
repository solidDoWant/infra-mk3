# ci-tools

The shared Tekton CI of the agent projects. A project has no CI scripts of its
own: its `.tekton/` PipelineRuns point at the shared Pipelines in `ci-tekton`
(`cluster/gitops/ci/tekton/pipelines/`), and its `ci.yaml` says what its
stages are and what a release publishes. The Pipelines run this image, pinned
by digest, on each run's dind.

| Command | What it does |
|---|---|
| `ci-config` | Reads and checks `ci.yaml`; the format is in its help (`ci-config`). |
| `ci-stages pull_request\|push` | Builds the project's CI image from its `flake.nix` (`ci-image`), runs the stages at once in it, and writes the stage results. |
| `ci-release <version>` | Builds the release assets and images, tags `latest` for a final version, pushes the charts, creates the GitHub release and uploads the assets. |
| `ci-cleanup` | Trims the Docker and Go caches after a push run. |
| `ci-report` | Gives each stage a check run (the Pipelines' report task). |
| `ci-pr-labels` | A pull request's labels, for the test guard. |

No pod holds a credential: registrygate pushes images for the `ci-release`
ServiceAccount, and githubgate's interceptor sends every GitHub request.

## Testing and publishing

- `make test`: the unit tests and shellcheck, in the image.
- `make e2e`: the fixture project (`tests/fixture/`) through `ci-stages` and a dry-run `ci-release`. It needs a Tekton `docker` Task's dind, so it runs in infra-mk3's CI (`.tekton/ci-tools/`), not on a workstation.
- A merge to master that changes this directory pushes `ghcr.io/soliddowant/ci-tools:<content hash>`. The run prints the digest; pin it in the shared Pipelines (`cluster/gitops/ci/tekton/pipelines/`).
