#!/bin/sh
# Writes the CA bundle the stage containers trust to the file named by the
# first argument: the task pod's system CAs, and, when the task pod is
# intercepted by githubgate, the interceptor's CAs too, so that the stage
# containers (which share the pod's network, so their GitHub traffic goes
# through the interceptor) accept the certificates it presents.
#
#   scripts/ci/ca-bundle.sh <output file>
#
# An intercepted pod is recognised by the pod CA in githubgate's trust mount
# (TRUST_DIR, /var/run/githubgate/trust by default), which every container of
# the pod gets. The step container gets the trust mount and the trust variables
# but none of the GITHUBGATE_INTERCEPT_* variables, which the webhook sets only
# in its own container, so those are used when present but never relied on.
#
# SYSTEM_CA overrides the system bundle's path (for tests). The injected CAs
# come from the trust mount's pod CA, from the pod's own trust file
# (SSL_CERT_FILE, joined with the proxy CA by the injection) and from
# GITHUBGATE_INTERCEPT_PROXY_CA and GITHUBGATE_INTERCEPT_EXTRA_CA, each PEM text
# or @file.
set -eu

out="${1:?usage: ca-bundle.sh <output file>}"
pod_ca="${TRUST_DIR:-/var/run/githubgate/trust}/ca.crt"

cp "${SYSTEM_CA:-/etc/ssl/certs/ca-certificates.crt}" "$out"

# Not intercepted: the system bundle alone.
if [ ! -r "$pod_ca" ] && [ -z "${GITHUBGATE_INTERCEPT_PROXY_ADDRESS:-}" ]; then
	exit 0
fi

for file in "$pod_ca" "${SSL_CERT_FILE:-}"; do
	if [ -n "$file" ] && [ -r "$file" ]; then
		cat "$file" >>"$out"
		echo >>"$out"
	fi
done
for value in "${GITHUBGATE_INTERCEPT_PROXY_CA:-}" "${GITHUBGATE_INTERCEPT_EXTRA_CA:-}"; do
	case "$value" in
	"") ;;
	@*) cat "${value#@}" >>"$out" ;;
	*) printf '%s\n' "$value" >>"$out" ;;
	esac
done
