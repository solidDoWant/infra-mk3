#!/usr/bin/env sh
set -eu

# Pin Proxmox's serving leaf so the gateway BackendTLSPolicy can validate the
# re-encrypted connection (Proxmox uses a private CA; see backend-tls-policy.yaml).
# Scrapes the leaf off the TLS handshake and upserts it into the pinned ConfigMap;
# on a schedule this self-heals after a Proxmox cert regeneration.
#
# Configuration comes from the pod environment (see hr.yaml):
#   POD_NAMESPACE     namespace holding the pinned-cert ConfigMap (downward API)
#   PROXMOX_ADDRESS   host:port of the Proxmox API, e.g. 10.2.2.1:8006
#   PROXMOX_HOSTNAME  SNI + cert SAN to validate, e.g. proxmox-vm-host-01

: "${POD_NAMESPACE:?must be set}"
: "${PROXMOX_ADDRESS:?must be set}"
: "${PROXMOX_HOSTNAME:?must be set}"

CONFIGMAP="${PROXMOX_HOSTNAME}-leaf-cert"

leaf="$(echo | openssl s_client -connect "${PROXMOX_ADDRESS}" -servername "${PROXMOX_HOSTNAME}" 2>/dev/null | openssl x509 2>/dev/null)"

if ! printf '%s' "${leaf}" | grep -q "BEGIN CERTIFICATE"; then
  echo "ERROR: failed to scrape a certificate from ${PROXMOX_ADDRESS}" >&2
  exit 1
fi

# The hostname must be a SAN on the leaf, otherwise BackendTLSPolicy hostname
# validation would reject the connection after we pin it. Fail closed rather than
# pin a cert that can never validate.
if ! printf '%s' "${leaf}" | openssl x509 -noout -ext subjectAltName 2>/dev/null | grep -qF "${PROXMOX_HOSTNAME}"; then
  echo "ERROR: scraped cert does not list ${PROXMOX_HOSTNAME} as a SAN; refusing to pin" >&2
  exit 1
fi

# Server-side apply so we own only data.ca.crt and leave the Flux-managed shell
# (and its ssa: IfNotPresent label) untouched. Flux applies the empty ConfigMap
# once and then steps back, so there is no apply conflict to force through.
kubectl create configmap "${CONFIGMAP}" \
  --namespace "${POD_NAMESPACE}" \
  --from-literal=ca.crt="${leaf}" \
  --dry-run=client -o yaml \
  | kubectl apply --server-side --field-manager=proxmox-cert-refresher -f -

echo "Pinned Proxmox leaf certificate to configmap ${POD_NAMESPACE}/${CONFIGMAP}"
