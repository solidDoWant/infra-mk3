#!/usr/bin/env bash
# Tests of lib/ca-bundle.sh: the injected interceptor CAs land in the
# stage CA bundle of an intercepted pod, and a pod that is not intercepted
# gets the system bundle as is.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "ca-bundle_test: $*" >&2; exit 1; }

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
# The script only joins PEM text, so each CA is a PEM block with a unique body.
mkcert() { printf -- '-----BEGIN CERTIFICATE-----\n%s\n-----END CERTIFICATE-----\n' "body-of-$1" >"$dir/$1.pem"; }
for name in system proxy extra inline joined; do mkcert "$name"; done

# Not intercepted: the bundle is the system bundle, whatever the trust variables say.
SYSTEM_CA="$dir/system.pem" TRUST_DIR="$dir/no-trust" SSL_CERT_FILE="$dir/proxy.pem" ./lib/ca-bundle.sh "$dir/plain.crt"
cmp -s "$dir/system.pem" "$dir/plain.crt" || fail "a pod that is not intercepted got more than the system CAs"

# Intercepted: the joined trust file, the proxy CA and the extra CA are in.
cat "$dir/system.pem" "$dir/joined.pem" >"$dir/joined.crt"
SYSTEM_CA="$dir/system.pem" TRUST_DIR="$dir/no-trust" GITHUBGATE_INTERCEPT_PROXY_ADDRESS=proxy:443 SSL_CERT_FILE="$dir/joined.crt" \
	GITHUBGATE_INTERCEPT_PROXY_CA="@$dir/proxy.pem" GITHUBGATE_INTERCEPT_EXTRA_CA="$(cat "$dir/inline.pem")" \
	./lib/ca-bundle.sh "$dir/intercepted.crt"
for name in system proxy inline joined; do
	grep -qF "$(sed -n 2p "$dir/$name.pem")" "$dir/intercepted.crt" || fail "the $name CA is missing from the bundle"
done

# Only the proxy CA variable, no trust file: still in.
SYSTEM_CA="$dir/system.pem" TRUST_DIR="$dir/no-trust" GITHUBGATE_INTERCEPT_PROXY_ADDRESS=proxy:443 GITHUBGATE_INTERCEPT_PROXY_CA="@$dir/extra.pem" \
	./lib/ca-bundle.sh "$dir/varonly.crt"
grep -qF "$(sed -n 2p "$dir/extra.pem")" "$dir/varonly.crt" || fail "the CA named by the variable is missing"

# A real intercepted Tekton step: the trust mount holds the pod CA, the trust
# variables point at it, and none of the helper's GITHUBGATE_INTERCEPT_*
# variables are set (the webhook sets those only in its own container).
mkdir -p "$dir/trust"
cp "$dir/proxy.pem" "$dir/trust/ca.crt"
cat "$dir/system.pem" "$dir/proxy.pem" >"$dir/trust/bundle.crt"
env -u GITHUBGATE_INTERCEPT_PROXY_ADDRESS -u GITHUBGATE_INTERCEPT_PROXY_CA -u GITHUBGATE_INTERCEPT_EXTRA_CA \
	SYSTEM_CA="$dir/system.pem" TRUST_DIR="$dir/trust" SSL_CERT_FILE="$dir/trust/bundle.crt" \
	NODE_EXTRA_CA_CERTS="$dir/trust/ca.crt" ./lib/ca-bundle.sh "$dir/step.crt"
grep -qF "$(sed -n 2p "$dir/proxy.pem")" "$dir/step.crt" || fail "the pod CA from the trust mount is missing from the bundle"
echo "ca-bundle_test: passed"
