#!/bin/bash
# Downloads the model, writes openarc_config.json, then starts openarc
# long enough for compile_model() to populate the OV cache. Exits when
# the model reports loaded. A warm cache lets future compile_model()
# calls skip graph optimization, which is what drives the load-time
# memory peak.
set -euo pipefail

: "${OPENARC_CONFIG_FILE:?required}"
: "${OPENARC_OV_CACHE_DIR:?required}"
: "${OPENARC_AUTOLOAD_MODEL:?required}"
: "${MODEL_PATH:?required}"
: "${MODEL_TYPE:?required}"
: "${HF_REPO:?required}"
ENGINE=${ENGINE:-openvino}
DEVICE=${DEVICE:-GPU}

mkdir -p "${MODEL_PATH}"
# huggingface-cli is idempotent (etag skip + resume on partials), so we
# always invoke it. The xet-backed transport can deadlock on connection
# drops and never return; wrap each attempt with a hard timeout and
# retry so a hung download eventually progresses on the resume.
for attempt in 1 2 3 4 5; do
  if timeout 240 huggingface-cli download "${HF_REPO}" --local-dir "${MODEL_PATH}"; then
    break
  fi
  if [[ "${attempt}" -eq 5 ]]; then
    echo "Download failed after 5 attempts" >&2
    exit 1
  fi
  echo "Download attempt ${attempt} timed out, retrying..." >&2
  sleep 5
done

# Truncate first so stale top-level fields from older schemas don't
# survive a rerun — `openarc add` only updates a single model entry.
mkdir -p "$(dirname "${OPENARC_CONFIG_FILE}")"
: > "${OPENARC_CONFIG_FILE}"
openarc add \
  --model-name="${OPENARC_AUTOLOAD_MODEL}" \
  --model-path="${MODEL_PATH}" \
  --engine="${ENGINE}" \
  --model-type="${MODEL_TYPE}" \
  --device="${DEVICE}"

# OpenVINO would auto-create the cache dir, but doing it here surfaces
# permission errors before the long compile starts rather than after.
mkdir -p "${OPENARC_OV_CACHE_DIR}"

openarc serve start --host 0.0.0.0 --port 8000 &
SERVER_PID=$!
trap 'kill ${SERVER_PID} 2>/dev/null || true' EXIT

for i in $(seq 1 60); do
  if curl -sf http://localhost:8000/v1/models >/dev/null 2>&1; then
    echo "Server ready after ${i}s; loading ${OPENARC_AUTOLOAD_MODEL}"
    openarc load "${OPENARC_AUTOLOAD_MODEL}"
    # `openarc load` returns 0 even on compile failure (it just POSTs and
    # reports the server response). /openarc/status reports per-model
    # `status`, which is "loaded" only after a successful compile; this
    # is the only signal that distinguishes registered-but-failed from
    # actually-usable. Only one model is ever loaded so substring checks
    # on the response are enough — no JSON parsing needed.
    resp=$(curl -sf http://localhost:8000/openarc/status)
    if [[ "${resp}" == *"\"model_name\":\"${OPENARC_AUTOLOAD_MODEL}\""* \
       && "${resp}" == *"\"status\":\"loaded\""* ]]; then
      echo "Model loaded; OV cache populated at ${OPENARC_OV_CACHE_DIR}"
      exit 0
    fi
    echo "Model failed to load: ${resp}" >&2
    exit 1
  fi
  sleep 1
done

echo "Server never became ready within 60s" >&2
exit 1
