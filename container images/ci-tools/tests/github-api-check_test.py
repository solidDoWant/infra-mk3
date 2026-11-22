#!/usr/bin/env python3
"""Tests of github-api-check.py against a local HTTPS fake of the GitHub API.

Each run mimics a stage container of the CI image: /etc/devshell.sh has set
NIX_SSL_CERT_FILE to Nix's public bundle (here a bundle without the fake's CA),
and the stage environment (stage-env.sh, or the old one that set only
SSL_CERT_FILE) then names the stage CA bundle, CI_CA.

The fake's certificate is a throwaway one made at run time with Go's
crypto/tls/generate_cert.go, since the dev shell has no openssl.
"""
import http.server
import json
import os
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.join(os.path.dirname(HERE), "lib")
SCRIPT = os.path.join(LIB, "github-api-check.py")
STAGE_ENV = 'source "$STAGE_ENV_FILE"'
# What the stage containers ran before stage-env.sh: only Python's own variable.
OLD_STAGE_ENV = 'export SSL_CERT_FILE="$CI_CA"'
CA_VARIABLES = ("SSL_CERT_FILE", "NIX_SSL_CERT_FILE", "CURL_CA_BUNDLE", "GIT_SSL_CAINFO", "REQUESTS_CA_BUNDLE")


def generate_cert(directory):
    # A self-signed P-256 certificate for 127.0.0.1, which is its own CA.
    cert, key = os.path.join(directory, "cert.pem"), os.path.join(directory, "key.pem")
    subprocess.run(
        ["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes",
         "-keyout", key, "-out", cert, "-days", "1", "-subj", "/CN=127.0.0.1",
         "-addext", "subjectAltName=IP:127.0.0.1", "-addext", "basicConstraints=critical,CA:TRUE"],
        capture_output=True,
        check=True,
    )
    return cert, key


class FakeGitHub(http.server.BaseHTTPRequestHandler):
    status = 200
    body = {}

    def log_message(self, *args):
        pass

    def do_GET(self):
        data = json.dumps(self.body).encode()
        self.send_response(self.status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


@unittest.skipUnless(shutil.which("go"), "go is needed to make the fake's certificate")
class QuietServer(http.server.ThreadingHTTPServer):
    """Ignores the connections a client drops on purpose (a failed TLS handshake)."""

    def handle_error(self, request, client_address):
        if isinstance(sys.exc_info()[1], (ConnectionError, ssl.SSLError)):
            return
        super().handle_error(request, client_address)


class GitHubAPICheckTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.TemporaryDirectory()
        cls.cert, cls.key = generate_cert(cls.dir.name)
        other = os.path.join(cls.dir.name, "other")
        os.mkdir(other)
        cls.other_cert, _ = generate_cert(other)

    @classmethod
    def tearDownClass(cls):
        cls.dir.cleanup()

    def setUp(self):
        FakeGitHub.status = 200
        FakeGitHub.body = {"full_name": "o/r"}
        self.server = QuietServer(("127.0.0.1", 0), FakeGitHub)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, self.key)
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def run_script(self, cafile=None, stage_env=STAGE_ENV):
        env = {name: value for name, value in os.environ.items() if name not in CA_VARIABLES}
        env.update(
            CI_GITHUB_API_URL=f"https://127.0.0.1:{self.server.server_port}",
            CI_CA=cafile or self.cert,
            NIX_SSL_CERT_FILE=self.other_cert,
            OTHER_CA=self.other_cert,
            STAGE_ENV_FILE=os.path.join(LIB, "stage-env.sh"),
            PYTHON=sys.executable,
            SCRIPT=SCRIPT,
        )
        command = stage_env + ' && exec "$PYTHON" -I "$SCRIPT" o/r'
        return subprocess.run(["bash", "-c", command], env=env, capture_output=True, text=True, timeout=120)

    def test_passes_for_the_repository(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("o/r", result.stdout)

    def test_passes_on_an_http_error_status_over_verified_tls(self):
        for status in (403, 404):
            with self.subTest(status=status):
                FakeGitHub.status = status
                FakeGitHub.body = {"message": "Forbidden"}
                result = self.run_script()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"HTTP {status}", result.stdout)

    def test_checks_with_python_and_curl(self):
        FakeGitHub.status = 403
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("from Python in a stage container: GET /repos/o/r: HTTP 403", result.stdout)
        self.assertIn("from curl in a stage container: GET /repos/o/r: HTTP 403", result.stdout)

    def test_fails_when_the_stage_environment_leaves_nix_ssl_cert_file_on_another_bundle(self):
        for status in (200, 403):
            with self.subTest(status=status):
                FakeGitHub.status = status
                result = self.run_script(stage_env=OLD_STAGE_ENV)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("from Python failed, the stage CA bundle or the interception is broken", result.stderr)

    def test_fails_when_curl_does_not_trust_the_server(self):
        result = self.run_script(stage_env=STAGE_ENV + ' && export CURL_CA_BUNDLE="$OTHER_CA"')
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("from curl failed, the stage CA bundle or the interception is broken", result.stderr)

    def test_fails_on_a_success_for_another_repository(self):
        FakeGitHub.body = {"full_name": "o/other"}
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("another repository", result.stderr)

    def test_fails_when_the_certificate_is_not_in_the_bundle(self):
        for status in (200, 403):
            with self.subTest(status=status):
                FakeGitHub.status = status
                result = self.run_script(cafile=self.other_cert)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("CA bundle or the interception is broken", result.stderr)


if __name__ == "__main__":
    unittest.main()
