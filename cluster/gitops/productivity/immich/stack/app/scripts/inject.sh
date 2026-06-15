#!/usr/bin/env sh
# Provisions one EPHEMERAL, random Immich API key per active user so the stacker
# can run against every user in a single invocation. Keys are minted fresh each
# run and the plaintext only ever lives in the pod's emptyDir env file (gone when
# the pod ends); the leftover DB rows hold only an unsalted SHA-256 of a 256-bit
# random token, so they are unusable afterwards and are reaped by the DELETE at
# the start of the next run.
#
# Couples to Immich's internal `api_keys` schema + its (unsalted SHA-256) key
# hashing — revisit on major Immich upgrades.
set -eu

# One statement: reap last run's keys, mint a fresh random key per active
# user (key column stores sha256(token), matching how Immich validates),
# and return the plaintext tokens comma-joined for the env file.
tokens=$(psql -qtA -v ON_ERROR_STOP=1 <<'SQL'
DELETE FROM api_keys WHERE name LIKE 'immich-stack/%';
WITH new_keys AS MATERIALIZED (
  -- MATERIALIZED so the volatile token is computed once: the hash stored in
  -- api_keys must be derived from the exact token returned to the env file.
  SELECT id AS user_id,
         replace(gen_random_uuid()::text, '-', '')
           || replace(gen_random_uuid()::text, '-', '') AS token
  FROM users
  WHERE "deletedAt" IS NULL
),
ins AS (
  INSERT INTO api_keys (name, key, "userId", permissions)
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
