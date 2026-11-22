#!/bin/sh
# Tests scripts/ci/changed-files.sh against a throwaway repository, for a PR
# that merges master with a merge commit and for one whose merge is a no-op.
set -eu
script="$(cd "$(dirname "$0")" && pwd)/changed-files.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q -b master .
git config user.email t@t
git config user.name t
git config commit.gpgsign false
echo base >base.txt
git add base.txt
git commit -q -m base
git update-ref refs/remotes/origin/master HEAD

# A PR based on master's tip: merging master is a no-op.
git checkout -q -b pr
echo one >one.txt
git add one.txt
git commit -q -m one
git merge -q --no-ff --no-edit origin/master
got=$("$script")
[ "$got" = one.txt ] || { echo "no-op merge: got '$got', want one.txt" >&2; exit 1; }

# Master moves on: merging it creates a commit, and its files do not count.
git checkout -q master
echo other >other.txt
git add other.txt
git commit -q -m other
git update-ref refs/remotes/origin/master HEAD
git checkout -q pr
git merge -q --no-ff --no-edit origin/master
got=$("$script")
[ "$got" = one.txt ] || { echo "merge commit: got '$got', want one.txt" >&2; exit 1; }
# A rename lists the old path too, whatever diff.renames says.
git config diff.renames true
mkdir -p scripts docs
echo content >scripts/moved.txt
git add scripts/moved.txt
git commit -q -m add-moved
git update-ref refs/remotes/origin/master HEAD
git mv scripts/moved.txt docs/moved.txt
git commit -q -m move
got=$("$script" | sort | tr '\n' ' ')
[ "$got" = "docs/moved.txt scripts/moved.txt " ] || { echo "rename: got '$got'" >&2; exit 1; }
echo "changed-files_test.sh: ok"
