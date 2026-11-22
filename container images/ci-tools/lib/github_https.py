"""The one way the CI scripts open an HTTPS request to GitHub.

Every request uses urllib's default TLS settings, with no context of its own,
so it trusts exactly what the dev shell's other tools (curl, git) trust: in a
stage container, the stage CA bundle that lib/stage-env.sh names in
NIX_SSL_CERT_FILE and SSL_CERT_FILE. The stage TLS check (github-api-check.py)
and the release upload (upload-release-assets.py) both use it, so a pull
request run proves the path that a release uses, and a stage environment that
leaves a variable pointing at another bundle fails that check. Verification is
never turned off.
"""
import urllib.request


def urlopen(request, timeout):
    """urllib.request.urlopen with the default TLS settings."""
    return urllib.request.urlopen(request, timeout=timeout)
