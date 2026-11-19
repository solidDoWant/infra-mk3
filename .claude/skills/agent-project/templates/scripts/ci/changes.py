#!/usr/bin/env python3
"""Decides which CI stages run on Tekton, by the path rules below.

Reads the changed files, one per line, on stdin and prints the selected
stages, space-separated, in a fixed order. A push to master runs every stage
whatever changed.

    git diff --name-only BASE HEAD | scripts/ci/changes.py pull_request
    scripts/ci/changes.py push </dev/null

Needs Python 3.13 or later (PurePath.full_match); it runs in the CI image.

TEMPLATE: keep STAGES in step with command_of in scripts/ci/stages.sh, and
add rules as the project grows (e.g. test-only changes skip e2e).
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
DOCS = ("**/*.md", "docs/**", "scripts/docs/**")

STAGES = ("lint", "unit", "generate", "integration", "e2e", "docs")


def matches(path, patterns):
    """Whether path matches any glob: `*` stays inside one path segment, `**`
    spans any number of them, and dot files match like any other."""
    pure = pathlib.PurePosixPath(path)
    return any(pure.full_match(pattern) for pattern in patterns)


def select(event, files):
    """Returns the stages to run, in STAGES order."""
    if event == "push":
        code = docs = True
    else:
        code = any(not matches(f, NOT_CODE) for f in files)
        docs = any(matches(f, DOCS) for f in files)
    selected = {stage: code for stage in STAGES}
    selected["docs"] = docs
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
