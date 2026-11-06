## Container images

**No Docker Hub (owner rule).** Docker Hub rate-limits anonymous pulls per address, and its pulls fail CI. Every container image this repo references comes from the first of these registries that publishes it:
1. `ghcr.io`;
2. `quay.io`;
3. `mirror.gcr.io`, Google's Docker Hub mirror, only when neither publishes the image. It serves the same digests. Use `mirror.gcr.io/library/<name>` for Docker official images, and `mirror.gcr.io/<org>/<name>` for the rest.

The rule covers every place an image can appear: tests and testcontainers, e2e manifests, the kind node image, Helm chart defaults, Dockerfile `FROM` lines, CI service containers and docs examples.

- Never write `docker.io/...`, and never an unqualified name such as `postgres` or `busybox`. The runtime resolves those to Docker Hub.
- Pin every image by digest (`name:tag@sha256:...`). The tag is for people, and the digest is what is pulled.
- Before you add an image, check `ghcr.io` and `quay.io` for it (`crane ls` or `crane digest`). Say in the PR which registry you picked and why.
- `make lint` fails on an unqualified or `docker.io` image reference. Don't silence the check: change the reference.
