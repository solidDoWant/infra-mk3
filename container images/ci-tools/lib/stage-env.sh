# shellcheck shell=bash
# Sourced in a stage container after /etc/devshell.sh: makes every tool trust
# exactly the stage CA bundle, $CI_CA. The dev shell's OpenSSL (Python, curl,
# git) takes NIX_SSL_CERT_FILE before SSL_CERT_FILE, and /etc/devshell.sh sets
# it to Nix's public bundle, which lacks the interceptor and registry CAs; curl,
# git and Python requests also read their own variables.
: "${CI_CA:?CI_CA must name the stage CA bundle}"
export SSL_CERT_FILE="$CI_CA" NIX_SSL_CERT_FILE="$CI_CA" CURL_CA_BUNDLE="$CI_CA" \
	GIT_SSL_CAINFO="$CI_CA" REQUESTS_CA_BUNDLE="$CI_CA"
