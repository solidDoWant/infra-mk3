#!/usr/bin/env sh
# Provisions one EPHEMERAL, random Immich API key per active user so the stacker
# can run against every user in a single invocation. Keys are minted fresh each
# run and the plaintext only ever lives in the pod's emptyDir env file (gone when
# the pod ends); the leftover DB rows hold only an unsalted SHA-256 of a 256-bit
# random token, so they are unusable afterwards and are reaped by the DELETE at
# the start of the next run.
#
# Couples to Immich's internal api-key table + its (unsalted SHA-256) key
# hashing. Immich renames these tables between versions (api_key/"user" on
# v2.7.5; api_keys/users on newer releases), so the names are resolved at
# runtime below, preferring the newer plural form. The column names
# (name/key/"userId"/permissions, "user".id, "deletedAt") and the SHA-256
# hashing must still be re-verified on a major Immich upgrade.
set -eu

# Resolve the live table names, preferring the newer plural form. to_regclass
# returns NULL when the relation is absent, so coalesce picks the first that
# exists. The values are fixed literals we control (not DB-derived), so it is
# safe to interpolate them into the statement below.
exists() { [ "$(psql -qtAc "select to_regclass('$1') is not null")" = t ]; }
if exists api_keys; then key_tbl=api_keys; else key_tbl=api_key; fi
# "user" is a reserved word and must be quoted; "users" is not, but quoting it
# is harmless, so quote both uniformly.
if exists users; then usr_tbl='"users"'; else usr_tbl='"user"'; fi

# One statement: reap last run's keys, mint a fresh random key per active
# user (key column stores sha256(token), matching how Immich validates),
# and return the plaintext tokens comma-joined for the env file.
# NOTE: unquoted heredoc — only ${key_tbl}/${usr_tbl} are expanded; keep the SQL
# free of other shell metacharacters ($, backticks).
tokens=$(psql -qtA -v ON_ERROR_STOP=1 <<SQL
DELETE FROM ${key_tbl} WHERE name LIKE 'immich-stack/%';
WITH new_keys AS MATERIALIZED (
  -- MATERIALIZED so the volatile token is computed once: the hash stored in
  -- the api-key table must be derived from the exact token returned below.
  SELECT id AS user_id,
         replace(gen_random_uuid()::text, '-', '')
           || replace(gen_random_uuid()::text, '-', '') AS token
  FROM ${usr_tbl}
  WHERE "deletedAt" IS NULL
),
ins AS (
  INSERT INTO ${key_tbl} (name, key, "userId", permissions)
  SELECT 'immich-stack/' || user_id,
         sha256(convert_to(token, 'UTF8')),
         user_id,
         ARRAY[
           'user.read', 'asset.read',
           'stack.read', 'stack.create', 'stack.update', 'stack.delete'
         ]::varchar[]
  FROM new_keys
  RETURNING 1
)
SELECT string_agg(token, ',') FROM new_keys;
SQL
)

if [ -z "$tokens" ]; then
  echo "inject: no active users found; nothing to stack" >&2
  exit 1
fi

printf 'API_KEY=%s\n' "$tokens" > /keys/api-keys.env
echo "inject: provisioned ephemeral keys for $(echo "$tokens" | tr ',' '\n' | wc -l) user(s)" >&2
