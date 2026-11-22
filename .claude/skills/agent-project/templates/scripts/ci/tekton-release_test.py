#!/usr/bin/env python3
"""Checks the release PipelineRun's workspaces: none may be backed by a claim,
which makes Tekton start an affinity-assistant pod that the cluster refuses
to run as the release ServiceAccount."""

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
FILES = [ROOT / "scripts/ci/tekton-release.yaml.tmpl", ROOT / ".tekton/release.yaml"]


def run_workspaces(text):
    """Returns {name: kind} for the PipelineRun's spec.workspaces list."""
    block = re.search(r"^  workspaces:\n((?:    .*\n|\n)+)", text, re.M)
    assert block, "no spec.workspaces"
    result = {}
    name = None
    for line in block.group(1).splitlines():
        found = re.match(r"    - name: (\S+)", line)
        if found:
            name = found.group(1)
            continue
        kind = re.match(r"      (emptyDir|volumeClaimTemplate|persistentVolumeClaim|secret|configMap)\b", line)
        if kind and name:
            result[name] = kind.group(1)
    return result


def tasks_using(text, workspace):
    return len(re.findall(r"^\s+workspace: %s$" % re.escape(workspace), text, re.M))


class ReleaseWorkspaceTest(unittest.TestCase):
    def test_no_workspace_is_a_claim(self):
        for path in FILES:
            text = path.read_text()
            for name, kind in run_workspaces(text).items():
                self.assertNotIn(kind, ("volumeClaimTemplate", "persistentVolumeClaim"), "%s: workspace %s" % (path.name, name))

    def test_no_workspace_is_shared_by_tasks(self):
        for path in FILES:
            text = path.read_text()
            for name in run_workspaces(text):
                self.assertLessEqual(tasks_using(text, name), 1, "%s: workspace %s" % (path.name, name))

    def test_detects_a_claim(self):
        text = "spec:\n  workspaces:\n    - name: source\n      volumeClaimTemplate:\n        spec: {}\n"
        self.assertEqual(run_workspaces(text), {"source": "volumeClaimTemplate"})


if __name__ == "__main__":
    unittest.main()
