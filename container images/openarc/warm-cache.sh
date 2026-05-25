#!/bin/bash
# Main setup-Job container. Starts the openarc server once, loads every
# model named in OPENARC_AUTOLOAD_MODEL (space-separated, already
# registered in openarc_config.json by the per-model init containers),
# then exits when each reports status="loaded". Loading triggers the
# OpenVINO compile path, which writes blobs into each model's --cache-dir
# so the runtime pod boots into a warm cache and avoids the high-memory
# cold-compile peak.
set -euo pipefail

: "${OPENARC_AUTOLOAD_MODEL:?required}"

openarc serve start --host 0.0.0.0 --port 8000 &
SERVER_PID=$!
trap 'kill ${SERVER_PID} 2>/dev/null || true' EXIT

for i in $(seq 1 60); do
  if curl -sf http://localhost:8000/v1/models >/dev/null 2>&1; then
    echo "Server ready after ${i}s; loading ${OPENARC_AUTOLOAD_MODEL}"
    # Unquoted on purpose: word-split into positional args for
    # `openarc load`'s variadic positional.
    # shellcheck disable=SC2086
    openarc load ${OPENARC_AUTOLOAD_MODEL}
    # `openarc load` returns 0 even on per-model compile failure (it
    # just POSTs and reports the server response). /openarc/status
    # reports per-model `status`, which is "loaded" only after a
    # successful compile — the only signal that distinguishes
    # registered-but-failed from actually-usable. exec hands the exit
    # code straight back.
    # shellcheck disable=SC2086
    exec /bin/check-models-loaded ${OPENARC_AUTOLOAD_MODEL}
  fi
  sleep 1
done

echo "Server never became ready within 60s" >&2
exit 1
