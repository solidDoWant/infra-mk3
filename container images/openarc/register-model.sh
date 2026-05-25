#!/bin/bash
# Downloads a single OpenVINO model from HuggingFace into the shared
# cache PVC and registers it in openarc_config.json via `openarc add`.
# Designed to run as one init container per model: each instance gets
# its own MODEL_NAME / HF_REPO / MODEL_TYPE / ENGINE env vars, and the
# config file accumulates entries across containers because save_model_config
# merges by model name.
#
# No openarc server is started here — compile + OV-cache warming happens
# in the main warm-cache container once every model has been registered.
set -euo pipefail

: "${OPENARC_CONFIG_FILE:?required}"
: "${OPENARC_CACHE_DIR:?required}"
: "${MODEL_NAME:?required}"
: "${HF_REPO:?required}"
: "${MODEL_TYPE:?required}"
: "${ENGINE:?required}"
DEVICE=${DEVICE:-GPU}

MODEL_PATH="${OPENARC_CACHE_DIR}/${MODEL_TYPE}/${MODEL_NAME}/${HF_REPO}/model"
OV_CACHE_DIR="${OPENARC_CACHE_DIR}/${MODEL_TYPE}/${MODEL_NAME}/${HF_REPO}/cache"

mkdir -p "${MODEL_PATH}" "${OV_CACHE_DIR}" "$(dirname "${OPENARC_CONFIG_FILE}")"

# huggingface-cli is idempotent (etag skip + resume on partials), so we
# always invoke it. The xet-backed transport can deadlock on connection
# drops and never return; wrap each attempt with a hard timeout and
# retry so a hung download eventually progresses on the resume.
for attempt in 1 2 3 4 5; do
  if timeout 240 huggingface-cli download "${HF_REPO}" --local-dir "${MODEL_PATH}"; then
    break
  fi
  if [[ "${attempt}" -eq 5 ]]; then
    echo "Download failed after 5 attempts for ${HF_REPO}" >&2
    exit 1
  fi
  echo "Download attempt ${attempt} timed out for ${HF_REPO}, retrying..." >&2
  sleep 5
done

openarc add \
  --model-name="${MODEL_NAME}" \
  --model-path="${MODEL_PATH}" \
  --engine="${ENGINE}" \
  --model-type="${MODEL_TYPE}" \
  --device="${DEVICE}" \
  --cache-dir="${OV_CACHE_DIR}"
