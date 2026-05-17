#!/bin/sh
# Honors the OPENARC_AUTOLOAD_MODEL env-var contract: serve start can't
# block on model load, so we launch it, wait for /v1/models, then load.
# Keep host/port matching what's baked into the asr-models config so
# save_server_config's diff check short-circuits.
set -eu

openarc serve start --host 0.0.0.0 --port 8000 &
SERVER_PID=$!

if [ -n "${OPENARC_AUTOLOAD_MODEL:-}" ]; then
  for i in $(seq 1 60); do
    if curl -sf -H "Authorization: Bearer ${OPENARC_API_KEY:-}" \
         http://localhost:8000/v1/models >/dev/null 2>&1; then
      echo "Server ready after $i seconds; loading $OPENARC_AUTOLOAD_MODEL"
      openarc load "$OPENARC_AUTOLOAD_MODEL" \
        || echo "WARN: failed to auto-load $OPENARC_AUTOLOAD_MODEL"
      break
    fi
    sleep 1
  done
fi

wait $SERVER_PID
