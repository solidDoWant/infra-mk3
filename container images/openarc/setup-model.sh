#!/bin/sh
# Args: MODEL_NAME MODEL_TYPE HF_REPO [ENGINE] [DEVICE]
set -eu

MODEL_NAME=$1
MODEL_TYPE=$2
HF_REPO=$3
ENGINE=${4:-ovgenai}
DEVICE=${5:-GPU}

# Path encodes (type, repo) so changing the repo in the HelmRelease values
# downloads into a fresh tree without stomping the previous one.
MODEL_DIR=/models/$MODEL_TYPE/$HF_REPO

export HF_HOME=/tmp/hf_cache

if ls "$MODEL_DIR"/*.xml >/dev/null 2>&1; then
  echo "Model already present at $MODEL_DIR, skipping download"
else
  mkdir -p "$MODEL_DIR"
  huggingface-cli download "$HF_REPO" --local-dir "$MODEL_DIR"
fi

# `openarc add` only updates a single model entry, so stale top-level fields
# from older versions would otherwise survive across upgrades.
: > /app/config/openarc_config.json
openarc add \
  --model-name="$MODEL_NAME" \
  --model-path="$MODEL_DIR" \
  --engine="$ENGINE" \
  --model-type="$MODEL_TYPE" \
  --device="$DEVICE"
