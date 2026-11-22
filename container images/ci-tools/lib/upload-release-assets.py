#!/usr/bin/env python3
"""Attaches the files of a directory to the GitHub release of a tag.

    upload-release-assets.py <tag> <directory>

A missing release is created first, with the `## <version>` section of
CHANGELOG.md at the tag as its notes; an existing release is left as it is. A
file whose name is already an asset of the release is left alone, so a
repeated run neither duplicates nor replaces assets.
Every request uses the default TLS settings, through github_https.py, the
request code of the stage TLS check; in a stage container they trust the
stage CA bundle (lib/stage-env.sh).
CI_GITHUB_API_URL and CI_GITHUB_UPLOAD_URL (tests) replace the GitHub
endpoints; CI_REPO is owner/name.
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

# -I leaves the script's directory off sys.path.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import github_https  # noqa: E402

API = os.environ.get("CI_GITHUB_API_URL", "https://api.github.com")
UPLOADS = os.environ.get("CI_GITHUB_UPLOAD_URL", "https://uploads.github.com")


def request(method, url, data=None, content_type=None, accept="application/vnd.github+json"):
    headers = {"Accept": accept}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, method=method, data=data, headers=headers)
    with github_https.urlopen(req, timeout=120) as response:
        return response.read()


def create_release(base, tag):
    version = tag[1:]
    changelog = request(
        "GET", f"{base}/contents/CHANGELOG.md?ref={urllib.parse.quote(tag)}", accept="application/vnd.github.raw+json"
    ).decode()
    section = re.search(r"^## " + re.escape(version) + r"\b[^\n]*\n(.*?)(?=^## |\Z)", changelog, re.M | re.S)
    if not section or not section.group(1).strip():
        sys.exit(f"CHANGELOG.md at {tag} has no ## {version} section")
    prerelease = "-rc." in version
    body = {
        "tag_name": tag,
        "name": tag,
        "body": section.group(1).strip() + "\n",
        "prerelease": prerelease,
        "make_latest": "false" if prerelease else "true",
    }
    release = json.loads(request("POST", f"{base}/releases", json.dumps(body).encode(), "application/json"))
    print(f"created release {tag}")
    return release


def main(tag, directory):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?", tag):
        sys.exit(f"not a version tag: {tag}")
    repo = os.environ["CI_REPO"]
    base = f"{API}/repos/{repo}"
    try:
        release = json.loads(request("GET", f"{base}/releases/tags/{urllib.parse.quote(tag)}"))
        print(f"release {tag} exists already; leaving it")
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        release = create_release(base, tag)
    release_id = release["id"]
    existing = set()
    page = 1
    while True:
        assets = json.loads(request("GET", f"{base}/releases/{release_id}/assets?per_page=100&page={page}"))
        existing.update(asset["name"] for asset in assets)
        if len(assets) < 100:
            break
        page += 1
    for name in sorted(os.listdir(directory)):
        if name in existing:
            print(f"asset {name} exists already; leaving it")
            continue
        with open(os.path.join(directory, name), "rb") as handle:
            body = handle.read()
        query = urllib.parse.urlencode({"name": name})
        request("POST", f"{UPLOADS}/repos/{repo}/releases/{release_id}/assets?{query}", body, "application/octet-stream")
        print(f"uploaded asset {name}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: upload-release-assets.py <tag> <directory>")
    main(sys.argv[1], sys.argv[2])
