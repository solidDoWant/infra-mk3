#!/bin/sh

# Applies couchgres server settings (kept in Postgres, not its config file) and
# creates or updates the device sync account. Idempotent.
set -eu

api() { 
  curl -fsS -u "${ADMIN_USERNAME}:${ADMIN_PASSWORD}" -H 'Content-Type: application/json' "$@"
}

set_config() {
  api -X PUT "${COUCHDB_URL}/_node/_local/_config/$1" -d "\"$2\"" >/dev/null
  echo "set $1=$2"
}

# Must come first: until it is set, anonymous requests are allowed.
set_config chttpd/require_valid_user true
# New databases are open to every authenticated user. The only
# non-admin account is the sync user, and only admins can create users.
set_config couchdb/default_security everyone
# couchgres' hard cap (livesync's own setup asks for 4GiB, which is rejected).
set_config chttpd/max_http_request_size 268435456
# Matches livesync's recommended max_document_size (50MB).
set_config couchgres_httpd/max_document_request_size 67108864

user_url="${COUCHDB_URL}/_users/org.couchdb.user:${SYNC_USERNAME}"
rev=$(api "${user_url}" 2>/dev/null | sed -n 's/.*"_rev":"\([^"]*\)".*/\1/p' || true)
rev_field=""

if [ -n "${rev}" ]; then
  rev_field="\"_rev\":\"${rev}\","
fi

api -X PUT "${user_url}" -d "{${rev_field}\"name\":\"${SYNC_USERNAME}\",\"password\":\"${SYNC_PASSWORD}\",\"roles\":[],\"type\":\"user\"}" >/dev/null
echo "updated user ${SYNC_USERNAME}"
