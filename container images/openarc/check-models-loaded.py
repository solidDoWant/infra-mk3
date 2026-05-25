#!/usr/bin/env python3
"""Liveness helper for the openarc runtime pod.

Queries /openarc/status and exits 0 iff every model name passed on argv
is reported with status="loaded". Used by the kubelet probe to detect
silent unloads (some bad transcription requests unload the model
without crashing the server) and to verify the warm-cache setup Job
finished cleanly.

Exit codes:
  0  every named model is loaded                     -> probe success
  0  the status endpoint timed out                   -> probe success
                                                        (server busy
                                                        mid-inference,
                                                        not dead)
  1  any model is missing or not in "loaded" state   -> probe failure
  1  any other request failure (HTTP/connection)     -> probe failure
"""
import json
import socket
import sys
import urllib.error
import urllib.request

URL = "http://localhost:8000/openarc/status"
# Stay below kubelet's exec timeoutSeconds (5s) so urlopen returns the
# timeout exception before kubelet SIGKILLs us, letting us distinguish
# "server busy" from "server gone".
TIMEOUT_S = 4

if len(sys.argv) < 2:
    print(f"usage: {sys.argv[0]} <model_name>...", file=sys.stderr)
    sys.exit(2)

expected = set(sys.argv[1:])

try:
    with urllib.request.urlopen(URL, timeout=TIMEOUT_S) as resp:
        data = json.load(resp)
except socket.timeout:
    sys.exit(0)
except (urllib.error.URLError, urllib.error.HTTPError, json.JSONDecodeError):
    sys.exit(1)

loaded = {
    m["model_name"]
    for m in data.get("models", [])
    if m.get("status") == "loaded"
}
sys.exit(0 if expected <= loaded else 1)
