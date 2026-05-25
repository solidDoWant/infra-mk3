#!/bin/sh
# Honors the OPENARC_AUTOLOAD_MODEL env-var contract: serve start can't
# block on model load, so we launch it, wait for /v1/models, then load.
# Keep host/port matching what's baked into the asr-models config so
# save_server_config's diff check short-circuits.
#
# OPENARC_AUTOLOAD_MODEL is treated as a whitespace-separated list so
# the runtime can pre-load multiple models registered in the config
# (e.g. an ASR model and an LLM in the same server).
#
# As PID 1, sh does not forward signals to backgrounded children, so without
# an explicit trap SIGTERM from the runtime would never reach the server
# and shutdown would stall until the kill-grace deadline.
set -eu

SERVER_PID=""

shutdown() {
  trap - TERM INT
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  exit 143
}

trap shutdown TERM INT

openarc serve start --host 0.0.0.0 --port 8000 &
SERVER_PID=$!

if [ -n "${OPENARC_AUTOLOAD_MODEL:-}" ]; then
  for i in $(seq 1 60); do
    if curl -sf  http://localhost:8000/v1/models >/dev/null 2>&1; then
      echo "Server ready after $i seconds; loading $OPENARC_AUTOLOAD_MODEL"
      # Unquoted on purpose: word-split into positional args so the
      # `openarc load` command's variadic positional accepts each name.
      # shellcheck disable=SC2086
      openarc load $OPENARC_AUTOLOAD_MODEL \
        || echo "WARN: failed to auto-load one or more of: $OPENARC_AUTOLOAD_MODEL"
      break
    fi
    sleep 1
  done
fi

# `wait` is interrupted by signals; the trap calls exit before we return here.
wait $SERVER_PID
