#!/usr/bin/env python3
"""Tests scripts/ci/changes.py's stage selection against the path rules of
the Tekton pipeline runs."""

import importlib.util
import pathlib
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "changes.py"
spec = importlib.util.spec_from_file_location("changes", SCRIPT)
changes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(changes)

GO_STAGES = ["lint", "unit", "fuzz", "generate", "integration"]
NON_GO_STAGES = ["lint", "unit", "generate", "integration"]


class SelectTest(unittest.TestCase):
    def check(self, files, expected, event="pull_request"):
        self.assertEqual(changes.select(event, files), expected)

    def test_a_push_runs_every_stage_but_the_scoreboard_whatever_changed(self):
        self.check([], GO_STAGES + ["e2e", "docs"], event="push")
        self.check(["README.md"], GO_STAGES + ["e2e", "docs"], event="push")

    def test_a_go_source_change_runs_the_go_stages_and_e2e(self):
        self.check(["internal/proxy/forward.go"], GO_STAGES + ["e2e"])

    def test_a_go_test_change_skips_e2e(self):
        self.check(["internal/proxy/forward_test.go"], GO_STAGES)
        self.check(["root_test.go"], GO_STAGES)

    def test_the_fuzz_stage_runs_only_for_changes_the_targets_build_from(self):
        self.check(["go.sum"], GO_STAGES + ["e2e"])
        self.check(["internal/proxy/testdata/fuzz/FuzzClassify/abc"], GO_STAGES + ["e2e"])
        self.check(["deploy/charts/{{PROJECT}}/values.yaml"], NON_GO_STAGES + ["e2e"])

    def test_an_e2e_harness_change_runs_e2e_even_when_it_is_a_test_file(self):
        self.check(["test/e2e/token_test.go"], GO_STAGES + ["e2e"])

    def test_a_markdown_change_runs_only_docs(self):
        self.check(["README.md"], ["docs"])
        self.check(["docs/admin/install.md"], ["docs"])

    def test_markdown_outside_the_root_and_docs_counts_as_code(self):
        # `*.md` matches only at the root.
        self.check(["deploy/charts/{{PROJECT}}/README.md"], NON_GO_STAGES + ["e2e", "docs"])

    def test_a_playbook_change_runs_nothing(self):
        self.check([".claude/agents/issue-worker.md"], ["docs"])
        self.check([".claude/settings.json"], [])
        self.check(["LICENSE", ".github/renovate.json5", ".github/renovate/groups.json5"], [])

    def test_a_non_markdown_docs_file_runs_nothing(self):
        self.check(["docs/images/diagram.svg"], [])

    def test_a_docs_script_change_runs_docs_and_the_go_stages(self):
        self.check(["scripts/docs/style_report.sh"], NON_GO_STAGES + ["e2e", "docs"])

    def test_a_checklist_change_alone_runs_the_scoreboard_and_docs(self):
        self.check(["docs/acceptance/phase-1.md"], ["docs", "scoreboard"])

    def test_a_checklist_change_with_code_skips_the_scoreboard(self):
        self.check(["docs/acceptance/phase-1.md", "go.mod"], GO_STAGES + ["e2e", "docs"])

    def test_one_code_file_among_docs_runs_the_go_stages(self):
        self.check(["docs/user/policy.md", "Makefile"], GO_STAGES + ["e2e", "docs"])

    def test_dot_files_count_as_code(self):
        self.check([".golangci.yml"], NON_GO_STAGES + ["e2e"])

    def test_no_changed_file_runs_nothing(self):
        self.check([], [])


if __name__ == "__main__":
    unittest.main()
