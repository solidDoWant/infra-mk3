#!/bin/sh

set -eu

BASE_DIR=/app/Data
PRELOAD_DATA_DIR=/preload/data
SOURCE_SERVER_CONFIG="${PRELOAD_DATA_DIR}/server.config"

cp -v "${SOURCE_SERVER_CONFIG}" "${BASE_DIR}/server.config"
echo "Setup complete"
