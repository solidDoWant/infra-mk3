#!/bin/sh
# Trims a Go cache directory tree to a size budget by deleting the least
# recently used files first. Go sets a cache entry's mtime when it uses the
# entry, so mtime is the recency. Files used in the last <protect seconds> (this
# run) are never deleted, so the trim can't empty the cache or remove what the
# next stage of the run needs. Only the build and lint caches are trimmed:
# deleting part of an extracted module in the module cache would leave a
# broken module that Go still trusts.
#
# It runs inside the CI image, with the script on stdin, so it uses
# only POSIX sh plus find, stat and sort.
#
#   trim-cache.sh <budget in KiB> <protect seconds> <directory>...
set -eu
budget="${1:?usage: trim-cache.sh <budget KiB> <protect seconds> <dir>...}"
protect="${2:?usage: trim-cache.sh <budget KiB> <protect seconds> <dir>...}"
shift 2
[ "$#" -gt 0 ] || { echo "trim-cache: no directory given" >&2; exit 1; }

list=$(mktemp)
trap 'rm -f "$list"' EXIT
# mtime, size in bytes, path.
find "$@" -type f -exec stat -c '%Y %s %n' {} + 2>/dev/null | sort -n >"$list" || true

budget_bytes=$((budget * 1024))
total=0
while read -r _mtime size _path; do
	total=$((total + size))
done <"$list"
echo "trim-cache: $((total / 1048576)) MiB in use, budget $((budget_bytes / 1048576)) MiB"
[ "$total" -gt "$budget_bytes" ] || exit 0

cutoff=$(($(date +%s) - protect))
removed=0
while read -r mtime size path; do
	[ "$total" -gt "$budget_bytes" ] || break
	# The list is oldest first, so every later entry is newer still.
	[ "$mtime" -lt "$cutoff" ] || break
	rm -f -- "$path"
	total=$((total - size))
	removed=$((removed + 1))
done <"$list"
echo "trim-cache: removed $removed files, $((total / 1048576)) MiB left"
