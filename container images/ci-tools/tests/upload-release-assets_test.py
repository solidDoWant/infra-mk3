#!/usr/bin/env python3
"""Tests of upload-release-assets.py against a local HTTPS fake of the GitHub release API.

The fake's certificate is a throwaway one made at run time, as in
github-api-check_test.py.
"""
import http.server
import importlib.util
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
SCRIPT = os.path.join(LIB, "upload-release-assets.py")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# Replaces the default certificate paths with argv[2] (or nothing), then
# prints the body of a GET of argv[3] made by upload-release-assets.py's
# request function.
DEFAULT_PATHS_REQUEST = """
import importlib.util, ssl, sys
def load_default_certs(context, purpose=ssl.Purpose.SERVER_AUTH):
    if sys.argv[2]:
        context.load_verify_locations(cafile=sys.argv[2])
ssl.SSLContext.load_default_certs = load_default_certs
spec = importlib.util.spec_from_file_location("upload_release_assets", sys.argv[1])
script = importlib.util.module_from_spec(spec)
spec.loader.exec_module(script)
sys.stdout.write(script.request("GET", sys.argv[3]).decode())
"""

generate_cert = load("github_api_check_test", os.path.join(HERE, "github-api-check_test.py")).generate_cert


class FakeGitHub(http.server.BaseHTTPRequestHandler):
    assets = {}
    uploads = 0
    exists = True
    created = []
    changelog = "# Changelog\n\n## 1.2.3\n\nNotes of one two three.\n\n## 1.2.2\n\nOld.\n"

    def log_message(self, *args):
        pass

    def reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/repos/o/r/releases/tags/v1.2.3" and self.exists:
            self.reply(200, {"id": 7})
        elif path == "/repos/o/r/contents/CHANGELOG.md":
            data = self.changelog.encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif path == "/repos/o/r/releases/7/assets":
            self.reply(200, [{"name": name} for name in self.assets])
        else:
            self.reply(404, {})

    def do_POST(self):
        path, _, query = self.path.partition("?")
        length = int(self.headers["Content-Length"])
        body = self.rfile.read(length)
        name = query.removeprefix("name=")
        if path == "/repos/o/r/releases":
            type(self).created.append(json.loads(body))
            type(self).exists = True
            self.reply(201, {"id": 7})
            return
        if path != "/repos/o/r/releases/7/assets":
            self.reply(404, {})
            return
        type(self).assets[name] = body
        type(self).uploads += 1
        self.reply(201, {"name": name})


@unittest.skipUnless(shutil.which("go"), "go is needed to make the fake's certificate")
class UploadReleaseAssetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.certs = tempfile.TemporaryDirectory()
        cls.cert, cls.key = generate_cert(cls.certs.name)
        other = os.path.join(cls.certs.name, "other")
        os.mkdir(other)
        cls.other_cert, _ = generate_cert(other)

    @classmethod
    def tearDownClass(cls):
        cls.certs.cleanup()

    def setUp(self):
        FakeGitHub.assets = {}
        FakeGitHub.uploads = 0
        FakeGitHub.exists = True
        FakeGitHub.created = []
        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeGitHub)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, self.key)
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f"https://127.0.0.1:{self.server.server_port}"
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        for name, content in (("crds.yaml", "crds"), ("checksums.txt", "sums")):
            with open(os.path.join(self.dir.name, name), "w") as handle:
                handle.write(content)

    def run_script(self, tag="v1.2.3", cafile=None):
        env = dict(
            os.environ,
            CI_GITHUB_API_URL=self.url,
            CI_GITHUB_UPLOAD_URL=self.url,
            CI_REPO="o/r",
            # As lib/stage-env.sh sets both in a stage container.
            SSL_CERT_FILE=cafile or self.cert,
            NIX_SSL_CERT_FILE=cafile or self.cert,
        )
        return subprocess.run(
            [sys.executable, "-I", SCRIPT, tag, self.dir.name], env=env, capture_output=True, text=True, timeout=60
        )

    def request_with_default_paths(self, cafile, default_cafile):
        """Makes one request, in a fresh process so that no SSL context is
        cached, with SSL_CERT_FILE set to cafile and the default certificate
        paths trusting only default_cafile (or nothing), as when the image's
        OpenSSL takes NIX_SSL_CERT_FILE before SSL_CERT_FILE."""
        env = dict(os.environ, SSL_CERT_FILE=cafile, NIX_SSL_CERT_FILE=cafile)
        url = f"{self.url}/repos/o/r/releases/tags/v1.2.3"
        return subprocess.run(
            [sys.executable, "-I", "-c", DEFAULT_PATHS_REQUEST, SCRIPT, default_cafile or "", url],
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )

    def test_trusts_the_default_certificate_paths_as_other_tools_do(self):
        result = self.request_with_default_paths(self.other_cert, self.cert)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"id": 7})

    def test_fails_when_the_default_paths_do_not_trust_the_server(self):
        result = self.request_with_default_paths(self.cert, None)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("CERTIFICATE_VERIFY_FAILED", result.stderr)

    def test_fails_without_uploading_when_the_bundle_does_not_trust_the_server(self):
        result = self.run_script(cafile=self.other_cert)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CERTIFICATE_VERIFY_FAILED", result.stderr)
        self.assertEqual(FakeGitHub.uploads, 0)

    def test_uploads_every_file(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(FakeGitHub.assets, {"crds.yaml": b"crds", "checksums.txt": b"sums"})

    def test_rerun_neither_duplicates_nor_replaces(self):
        self.run_script()
        FakeGitHub.assets["crds.yaml"] = b"original"
        FakeGitHub.uploads = 0
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(FakeGitHub.uploads, 0)
        self.assertEqual(FakeGitHub.assets["crds.yaml"], b"original")

    def test_uploads_only_the_missing_file(self):
        FakeGitHub.assets["crds.yaml"] = b"original"
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(FakeGitHub.uploads, 1)
        self.assertEqual(FakeGitHub.assets["checksums.txt"], b"sums")

    def test_creates_a_missing_release_with_the_changelog_section(self):
        FakeGitHub.exists = False
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(FakeGitHub.created), 1)
        release = FakeGitHub.created[0]
        self.assertEqual(release["tag_name"], "v1.2.3")
        self.assertEqual(release["body"], "Notes of one two three.\n")
        self.assertEqual(release["make_latest"], "true")
        self.assertFalse(release["prerelease"])
        self.assertEqual(set(FakeGitHub.assets), {"crds.yaml", "checksums.txt"})

    def test_leaves_an_existing_release_alone(self):
        self.run_script()
        self.assertEqual(FakeGitHub.created, [])

    def test_fails_without_a_changelog_section(self):
        FakeGitHub.exists = False
        FakeGitHub.changelog = "## 9.9.9\n\nOther.\n"
        self.addCleanup(setattr, FakeGitHub, "changelog", "# Changelog\n\n## 1.2.3\n\nNotes of one two three.\n\n## 1.2.2\n\nOld.\n")
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual(FakeGitHub.created, [])

    def test_refuses_a_tag_that_is_not_a_version(self):
        self.assertNotEqual(self.run_script("main").returncode, 0)


if __name__ == "__main__":
    unittest.main()
