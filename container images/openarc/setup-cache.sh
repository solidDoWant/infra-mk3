#!/bin/bash
# Downloads each model in OPENARC_MODELS_SPEC, writes a fresh
# openarc_config.json with one entry per model, then starts openarc long
# enough for compile_model() to populate each model's OV cache. Exits
# when every model reports loaded. A warm cache lets future
# compile_model() calls skip graph optimization, which is what drives
# the load-time memory peak.
set -euo pipefail

: "${OPENARC_CONFIG_FILE:?required}"
: "${OPENARC_CACHE_DIR:?required}"
# Multi-line, pipe-separated: name|hf_repo|model_type|engine (one per line).
: "${OPENARC_MODELS_SPEC:?required}"
DEVICE=${DEVICE:-GPU}

# Truncate first so stale top-level fields from older schemas don't
# survive a rerun. `openarc add` merges by model name into config["models"],
# so subsequent entries accumulate cleanly into the empty file.
mkdir -p "$(dirname "${OPENARC_CONFIG_FILE}")"
: > "${OPENARC_CONFIG_FILE}"

declare -a MODEL_NAMES
while IFS='|' read -r name repo model_type engine; do
  # Trim surrounding whitespace and skip blank lines from block scalars.
  name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
  [[ -z "${name}" ]] && continue
  repo="${repo#"${repo%%[![:space:]]*}"}"; repo="${repo%"${repo##*[![:space:]]}"}"
  model_type="${model_type#"${model_type%%[![:space:]]*}"}"; model_type="${model_type%"${model_type##*[![:space:]]}"}"
  engine="${engine#"${engine%%[![:space:]]*}"}"; engine="${engine%"${engine##*[![:space:]]}"}"

  model_path="${OPENARC_CACHE_DIR}/${model_type}/${name}/${repo}/model"
  ov_cache_dir="${OPENARC_CACHE_DIR}/${model_type}/${name}/${repo}/cache"

  echo "=== Preparing ${name} (repo=${repo}, type=${model_type}, engine=${engine}) ==="
  mkdir -p "${model_path}"

  # huggingface-cli is idempotent (etag skip + resume on partials), so we
  # always invoke it. The xet-backed transport can deadlock on connection
  # drops and never return; wrap each attempt with a hard timeout and
  # retry so a hung download eventually progresses on the resume.
  for attempt in 1 2 3 4 5; do
    if timeout 240 huggingface-cli download "${repo}" --local-dir "${model_path}"; then
      break
    fi
    if [[ "${attempt}" -eq 5 ]]; then
      echo "Download failed after 5 attempts for ${repo}" >&2
      exit 1
    fi
    echo "Download attempt ${attempt} timed out for ${repo}, retrying..." >&2
    sleep 5
  done

  # OpenVINO would auto-create the cache dir, but doing it here surfaces
  # permission errors before the long compile starts rather than after.
  mkdir -p "${ov_cache_dir}"

  openarc add \
    --model-name="${name}" \
    --model-path="${model_path}" \
    --engine="${engine}" \
    --model-type="${model_type}" \
    --device="${DEVICE}" \
    --cache-dir="${ov_cache_dir}"

  MODEL_NAMES+=("${name}")
done <<< "${OPENARC_MODELS_SPEC}"

if [[ ${#MODEL_NAMES[@]} -eq 0 ]]; then
  echo "OPENARC_MODELS_SPEC parsed to zero models" >&2
  exit 1
fi

openarc serve start --host 0.0.0.0 --port 8000 &
SERVER_PID=$!
trap 'kill ${SERVER_PID} 2>/dev/null || true' EXIT

for i in $(seq 1 60); do
  if curl -sf http://localhost:8000/v1/models >/dev/null 2>&1; then
    echo "Server ready after ${i}s; loading ${MODEL_NAMES[*]}"
    # `openarc load` accepts multiple names and loads them sequentially.
    openarc load "${MODEL_NAMES[@]}"
    # `openarc load` returns 0 even on per-model compile failure (it just
    # POSTs and reports the server response). /openarc/status reports
    # per-model `status`, which is "loaded" only after a successful
    # compile; this is the only signal that distinguishes
    # registered-but-failed from actually-usable.
    resp=$(curl -sf http://localhost:8000/openarc/status)
    # Each model object serializes "model_name" before "status", so a
    # substring match anchored on the name through "status":"loaded"
    # confirms that *this* model is loaded, not just that some other
    # model in the response happens to be loaded.
    failed=0
    for m in "${MODEL_NAMES[@]}"; do
      if [[ "${resp}" == *"\"model_name\":\"${m}\""*"\"status\":\"loaded\""* ]]; then
        echo "OK: ${m} loaded"
      else
        echo "FAIL: ${m} not loaded" >&2
        failed=1
      fi
    done
    if [[ ${failed} -ne 0 ]]; then
      echo "Status response: ${resp}" >&2
      exit 1
    fi
    echo "All models loaded; OV caches populated under ${OPENARC_CACHE_DIR}"
    exit 0
  fi
  sleep 1
done

echo "Server never became ready within 60s" >&2
exit 1
