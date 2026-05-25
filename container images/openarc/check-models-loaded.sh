#!/bin/bash
# Liveness helper: exits 0 if every model name passed on argv is present
# in /openarc/status with status="loaded". Used by the runtime pod's
# probe to detect silent unloads (some bad transcription requests
# unload the model without crashing the server).
#
# Exit codes:
#   0  every named model is loaded                     -> probe success
#   0  the status endpoint timed out (curl --max-time) -> probe success
#                                                         (server busy
#                                                         mid-inference,
#                                                         not dead)
#   1  any model is missing or not in "loaded" state   -> probe failure
#   1  any other curl failure (HTTP/connection)        -> probe failure
set -uo pipefail

if [[ $# -eq 0 ]]; then
  echo "usage: $0 <model_name>..." >&2
  exit 2
fi

# --max-time stays below the kubelet exec timeout so curl returns rc=28
# before kubelet SIGKILLs us, letting us distinguish "server busy" (28)
# from real errors (anything else).
resp=$(curl -sf --max-time 4 http://localhost:8000/openarc/status) || rc=$?
rc=${rc:-0}
[[ $rc -eq 28 ]] && exit 0
[[ $rc -ne 0 ]] && exit 1

# Each model is its own flat JSON object inside the "models" array; no
# nested {} appears within an object's fields (runtime_config can be {}
# but stays empty here). Extract the object containing this model_name
# with a balanced-pair-free regex, then check that *that* object also
# has status="loaded". Avoids a global "any model is loaded" check that
# would false-positive when one model is loaded and another is loading.
for m in "$@"; do
  obj=$(grep -oE "\{[^{}]*\"model_name\":\"${m}\"[^{}]*\}" <<< "${resp}") || {
    exit 1
  }
  [[ "${obj}" == *"\"status\":\"loaded\""* ]] || exit 1
done
