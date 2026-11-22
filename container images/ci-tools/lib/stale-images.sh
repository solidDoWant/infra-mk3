#!/bin/sh
# Reads `repository:tag` lines of the images in dockerd's store on stdin and
# prints those to remove: an image whose repository the tree still names, but
# at a tag it no longer names. Images of other repositories are never printed.
#
#   lib/stale-images.sh <file of the images the tree names> <stdin: stored images>
set -eu
keep="${1:?usage: stale-images.sh <file of kept images>}"
awk '
	NR == FNR {
		ref = $0
		sub(/@.*/, "", ref)
		kept[ref] = 1
		repo = ref
		sub(/:[^:\/]*$/, "", repo)
		repos[repo] = 1
		next
	}
	{
		# An image stored without a tag lists as `repository:<none>`, which
		# `docker image rm` rejects; dangling ones are left to `image prune`.
		if ($0 ~ /:<none>$/) next
		repo = $0
		sub(/:[^:\/]*$/, "", repo)
		if ((repo in repos) && !($0 in kept)) print $0
	}
' "$keep" -
