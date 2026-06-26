#!/usr/bin/env bash
# Pull a UniFi device's stored adoption key (x_authkey) from the controller's
# Mongo database, by MAC address.
#
# Why this is annoying:
#   - The controller image ships only `mongod`, no `mongo`/`mongosh` client shell.
#   - UniFi's bundled Mongo binds to 127.0.0.1:27117 inside the pod, so nothing
#     else in the cluster can reach it. `kubectl port-forward` does reach the pod
#     loopback, so we forward the port and query it from here.
#   - The controller runs an ancient MongoDB (3.6, wire v6); modern pymongo
#     refuses to talk to it, so we pin `pymongo<4`.
#
# Requires: kubectl (with context pointed at the cluster) and uv.
#
# Usage: ./get-device-authkey.sh <mac-address>
#   e.g. ./get-device-authkey.sh aa:bb:cc:dd:ee:ff
set -euo pipefail

MAC="${1:-}"
if [[ -z "$MAC" ]]; then
  echo "usage: $0 <mac-address>" >&2
  exit 1
fi

NAMESPACE="networking"
POD="statefulsets/unifi-controller"
PORT="27117"

# Forward the pod's loopback Mongo port and make sure we clean it up on exit.
kubectl port-forward -n "$NAMESPACE" "$POD" "${PORT}:${PORT}" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT

# Wait for the forward to come up.
for _ in $(seq 1 20); do
  (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null && { exec 3>&- 3<&-; break; }
  sleep 0.5
done

MAC="$MAC" PORT="$PORT" uv run --quiet --with 'pymongo<4' --no-project python3 - <<'PY'
import json, os
from pymongo import MongoClient

mac = os.environ["MAC"]
port = os.environ["PORT"]
c = MongoClient(f"mongodb://127.0.0.1:{port}", serverSelectionTimeoutMS=8000)
doc = c["ace"]["device"].find_one(
    {"mac": mac},
    {"_id": 0, "mac": 1, "x_authkey": 1, "cfgversion": 1},
)
if doc is None:
    raise SystemExit(f"no device found with mac {mac}")
print(json.dumps(doc, indent=2))
PY
