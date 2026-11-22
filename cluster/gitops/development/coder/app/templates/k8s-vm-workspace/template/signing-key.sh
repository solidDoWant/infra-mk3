#!/usr/bin/env bash
# Run by the signing-key Jobs (signing-keys.tf). Adds this workspace's SSH
# signing key to the owner's GitHub account (MODE=add), or deletes it
# (MODE=remove). The pod is intercepted by githubgate: requests to
# api.github.com go to githubgate, which sends them as the owner with a user
# access token this pod never sees, so there is no Authorization header here.
#
# Keys are matched by title, which ends in "(<workspace id>)". Both modes first
# delete every key of this workspace, so a key left by a stop that failed is
# gone after the next start.
set -euo pipefail

: "${MODE:?}" "${TITLE:?}" "${WORKSPACE_ID:?}"

api() {
  curl --silent --show-error --fail-with-body \
    --retry 5 --retry-connrefused --max-time 20 \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

remove_keys() {
  local keys id
  keys="$(api "https://api.github.com/user/ssh_signing_keys?per_page=100")"
  for id in $(jq -r --arg suffix "(${WORKSPACE_ID})" '.[] | select(.title | endswith($suffix)) | .id' <<<"${keys}"); do
    echo "Deleting signing key ${id}"
    api -X DELETE "https://api.github.com/user/ssh_signing_keys/${id}" >/dev/null
  done
}

case "${MODE}" in
add)
  : "${PUBLIC_KEY:?}"
  remove_keys
  echo "Adding signing key \"${TITLE}\""
  api -X POST "https://api.github.com/user/ssh_signing_keys" \
    -d "$(jq -n --arg title "${TITLE}" --arg key "${PUBLIC_KEY}" '{title: $title, key: $key}')" |
    jq -r '"Added signing key \(.id)"'
  ;;
remove)
  # A stop must never fail on this: the guest and its private key are gone
  # either way, and the next start deletes what is left.
  if ! remove_keys; then
    echo "Could not delete the signing keys; the next start deletes them" >&2
  fi
  ;;
*)
  echo "MODE must be add or remove, not ${MODE}" >&2
  exit 2
  ;;
esac
