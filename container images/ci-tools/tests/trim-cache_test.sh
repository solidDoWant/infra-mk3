#!/bin/sh
# Tests lib/trim-cache.sh: it removes the oldest files first, stops at
# the budget, and keeps files used in this run even over the budget.
set -eu
cd "$(dirname "$0")/../lib"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
now=$(date +%s)

# mk <name> <age in seconds>: a 1 KiB file last used that long ago.
mk() {
	mkdir -p "$dir/$(dirname "$1")"
	head -c 1024 /dev/zero >"$dir/$1"
	touch -d "@$((now - $2))" "$dir/$1"
}
left() { (cd "$dir" && find . -type f | sort | tr '\n' ' '); }
fail() { echo "trim-cache_test.sh: $1" >&2; exit 1; }

mk go/old 5000
mk go/older 6000
mk lint/mid 4000
mk go/new 3000
mk go/fresh 10

# Under the budget: nothing is removed.
/bin/sh ./trim-cache.sh 5 600 "$dir" >/dev/null
[ "$(left)" = "./go/fresh ./go/new ./go/old ./go/older ./lint/mid " ] || fail "under budget removed files: $(left)"

# Budget of 3 KiB: the oldest files go (go/older, go/old) and it stops at 3 KiB left.
/bin/sh ./trim-cache.sh 3 600 "$dir" >/dev/null
[ "$(left)" = "./go/fresh ./go/new ./lint/mid " ] || fail "oldest-first stop at budget gave: $(left)"

# Budget of 0: files used in this run stay.
/bin/sh ./trim-cache.sh 0 600 "$dir" >/dev/null
[ "$(left)" = "./go/fresh " ] || fail "protected file removed or others kept: $(left)"
echo "trim-cache_test.sh: ok"
