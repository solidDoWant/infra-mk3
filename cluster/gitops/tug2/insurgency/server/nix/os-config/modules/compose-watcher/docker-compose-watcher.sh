#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "$(date): $*"
}

# Require compose file as CLI argument
if [ $# -eq 0 ]; then
  echo "Error: Compose file path is required"
  echo "Usage: $0 <compose-file-path>"
  exit 1
fi

COMPOSE_FILE="$1"
# Watch the directory instead of individual files to handle ConfigMap atomic updates
WATCH_DIR=$(dirname "${COMPOSE_FILE}")
LAST_CHECKSUM=""

log "Using compose file: ${COMPOSE_FILE}"

# Function to deploy docker compose
deploy_compose() {
  log "Checking docker compose configuration..."
  
  if [ ! -f "${COMPOSE_FILE}" ]; then
    log "Docker compose file not found at ${COMPOSE_FILE}"
    return
  fi
  
  CURRENT_CHECKSUM=$(sha256sum "${COMPOSE_FILE}" 2>/dev/null | cut -d' ' -f1 || echo "")
  
  if [ "${CURRENT_CHECKSUM}" = "${LAST_CHECKSUM}" ]; then
    log "Configuration unchanged, skipping deployment"
    return
  fi
  
  log "Configuration changed, deploying docker compose..."
  docker-compose -f "${COMPOSE_FILE}" up -d
  
  LAST_CHECKSUM="${CURRENT_CHECKSUM}"
  log "Docker compose deployment completed"
}

# Initial deployment on startup
deploy_compose

# Watch for changes in the ConfigMap directory
# This handles Kubernetes' atomic ConfigMap updates
log "Starting to watch for ConfigMap changes in ${WATCH_DIR}"
while inotifywait -e modify,create,delete,move "${WATCH_DIR}" 2>/dev/null; do
  log "ConfigMap directory change detected"
  deploy_compose
done

# Capture the exit code from inotifywait
EC=$?
log "inotifywait exited with code ${EC}, service will be restarted by systemd"
exit $EC
