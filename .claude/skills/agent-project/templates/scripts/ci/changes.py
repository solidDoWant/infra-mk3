#!/usr/bin/env python3
"""Decides which CI stages run on Tekton, by the path rules below.

Reads the changed files, one per line, on stdin and prints the selected
stages, space-separated, in a fixed order. A push to master runs every stage
that a change to code runs, whatever changed: master runs test everything
merged so far.

    git diff --name-only BASE HEAD | scripts/ci/changes.py pull_request
    scripts/ci/changes.py push </dev/null
"""

import pathlib
import sys

# Files that cannot change what the build or the tests produce.
NOT_CODE = (
    "*.md",
    "docs/**",
    ".claude/**",
    "LICENSE",
    ".github/renovate.json5",
    ".github/renovate/**",
)
# Go test files are never built into the binaries and images e2e deploys.
NOT_E2E_CODE = NOT_CODE + ("**/*_test.go",)
E2E_HARNESS = ("test/e2e/**",)
ACCEPTANCE = ("docs/acceptance/**",)
DOCS = ("**/*.md", "scripts/docs/**")

# What the fuzz targets build from: Go sources and tests, the module files,
# the seed corpora and the Makefile that lists the targets.
FUZZ_INPUTS = ("**/*.go", "go.mod", "go.sum", "**/testdata/**", "Makefile")

STAGES = ("lint", "unit", "fuzz", "generate", "integration", "e2e", "docs", "scoreboard")


def matches(path, patterns):
    """Whether path matches any glob: `*` stays inside one path segment, `**`
    spans any number of them, and dot files match like any other."""
    pure = pathlib.PurePosixPath(path)
    return any(pure.full_match(pattern) for pattern in patterns)


def select(event, files):
    """Returns the stages to run, in STAGES order."""
    if event == "push":
        code = e2e = docs = fuzz = True
        acceptance = False
    else:
        code = any(not matches(f, NOT_CODE) for f in files)
        e2e = any(not matches(f, NOT_E2E_CODE) or matches(f, E2E_HARNESS) for f in files)
        docs = any(matches(f, DOCS) for f in files)
        fuzz = any(matches(f, FUZZ_INPUTS) for f in files)
        # The scoreboard's tests read the real checklist. When code changed,
        # the unit stage runs them already.
        acceptance = not code and any(matches(f, ACCEPTANCE) for f in files)
    selected = {
        "lint": code,
        "unit": code,
        "fuzz": fuzz,
        "generate": code,
        "integration": code,
        "e2e": e2e,
        "docs": docs,
        "scoreboard": acceptance,
    }
    return [stage for stage in STAGES if selected[stage]]


def main(argv):
    if len(argv) != 2 or argv[1] not in ("pull_request", "push"):
        print("usage: changes.py pull_request|push < changed-files", file=sys.stderr)
        return 2
    files = [line.strip() for line in sys.stdin if line.strip()]
    print(" ".join(select(argv[1], files)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
