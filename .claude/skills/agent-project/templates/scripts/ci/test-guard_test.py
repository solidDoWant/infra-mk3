#!/usr/bin/env python3
"""Tests scripts/ci/test-guard.py, the CI check that fails a pull request
which deletes or skips a checklist scenario test, against throwaway git
repositories holding a base and a head commit."""

import os
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
SCRIPT = ROOT / "scripts" / "ci" / "test-guard.py"

CHECKLIST = "docs/acceptance/phase-1.md"
E2E_TEST = "test/e2e/enable_test.go"
UNIT_TEST = "internal/policy/rules_test.go"

CHECKLIST_TEXT = """# Phase 1

- **AC-1-07 Enable.** A session enables a server.
  Tests: `test/e2e: TestEnable/enable creates a restricted namespace`
- **AC-1-11 Disable.** Disable removes the tools.
  Tests: `test/e2e: TestEnable/disable removes the tools`
- **AC-1-25 Block a tool.** A rule blocks a tool.
  Tests: `test/e2e: TestBlockATool`
- **AC-1-26 Block by workspace.** A rule matches a workspace glob.
  Tests: `internal/policy: TestRules`
"""

E2E_SOURCE = """//go:build e2e

package e2e

func TestEnable(t *testing.T) {
	t.Parallel()
	t.Run("enable creates a restricted namespace", func(t *testing.T) {
		requireNamespace(t)
	})
	t.Run("disable removes the tools", func(t *testing.T) {
		if os.Getenv("SLOW") == "" {
			t.Skip("slow")
		}
		requireDisabled(t)
	})
	t.Run("an unlisted test", func(t *testing.T) {})
}

func TestBlockATool(t *testing.T) {
	block(t)
}
"""

UNIT_SOURCE = """package policy

func TestRules(t *testing.T) {
	for _, test := range tests {
		s.Run(`workspace glob `+test.name, func(t *testing.T) {
			check(t, test)
		})
	}
}
"""


class TestGuard(unittest.TestCase):
    def setUp(self):
        self.repository = pathlib.Path(tempfile.mkdtemp())
        self.git("init", "-q", "-b", "master")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "test")
        self.git("config", "commit.gpgsign", "false")
        self.write(E2E_TEST, E2E_SOURCE)
        self.write(UNIT_TEST, UNIT_SOURCE)
        self.write(CHECKLIST, CHECKLIST_TEXT)
        self.commit("base")
        self.base = self.git("rev-parse", "HEAD").strip()

    def git(self, *arguments):
        return subprocess.run(["git", *arguments], cwd=self.repository, capture_output=True, text=True, check=True).stdout

    def write(self, path, content):
        target = self.repository / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def replace(self, path, old, new):
        content = (self.repository / path).read_text(encoding="utf-8")
        self.assertIn(old, content)
        self.write(path, content.replace(old, new, 1))

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)

    def guard(self, labels=""):
        self.commit("head")
        environment = dict(os.environ, TEST_GUARD_PR_LABELS=labels)
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), "--base", self.base],
            cwd=self.repository,
            env=environment,
            capture_output=True,
            text=True,
        )

    def assert_passes(self, completed):
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def assert_fails_naming(self, completed, *names):
        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        for name in names:
            self.assertIn(name, completed.stdout + completed.stderr)

    # Ordinary pull requests.

    def test_an_unchanged_tree_passes(self):
        self.assert_passes(self.guard())

    def test_an_edited_body_and_a_new_test_pass(self):
        self.replace(E2E_TEST, "requireNamespace(t)", "requireNamespace(t, restricted)")
        self.replace(E2E_TEST, '\tt.Run("an unlisted test"', '\tt.Run("call", func(t *testing.T) {})\n\tt.Run("an unlisted test"')
        self.assert_passes(self.guard())

    def test_moving_a_test_to_another_file_passes(self):
        self.replace(E2E_TEST, """func TestBlockATool(t *testing.T) {
	block(t)
}
""", "")
        self.write("test/e2e/rules_test.go", "package e2e\n\nfunc TestBlockATool(t *testing.T) {\n\tblock(t)\n}\n")
        self.assert_passes(self.guard())

    def test_deleting_an_unlisted_test_passes(self):
        self.replace(E2E_TEST, '\tt.Run("an unlisted test", func(t *testing.T) {})\n', "")
        self.assert_passes(self.guard())

    def test_an_existing_conditional_skip_kept_passes(self):
        self.replace(E2E_TEST, "requireDisabled(t)", "requireDisabled(t, now)")
        self.assert_passes(self.guard())

    def test_a_test_with_a_tag_in_its_name_but_not_listed_is_not_guarded(self):
        self.write("test/e2e/other_test.go", 'package e2e\n\nfunc TestOther(t *testing.T) {\n\tt.Run("[AC-1-08] call", nil)\n}\n')
        self.commit("tagged")
        self.base = self.git("rev-parse", "HEAD").strip()
        (self.repository / "test/e2e/other_test.go").unlink()
        self.assert_passes(self.guard())

    def test_it_takes_well_under_ten_seconds_on_this_repository(self):
        started = time.monotonic()
        completed = subprocess.run([sys.executable, "-I", str(SCRIPT), "--base", "HEAD"], cwd=ROOT, capture_output=True, text=True)
        self.assert_passes(completed)
        self.assertLess(time.monotonic() - started, 10)

    # Deleted, renamed and unlisted scenario tests.

    def test_deleting_a_listed_subtest_fails_naming_it(self):
        self.replace(E2E_TEST, """	t.Run("enable creates a restricted namespace", func(t *testing.T) {
		requireNamespace(t)
	})
""", "")
        self.assert_fails_naming(self.guard(), "deleted or renamed: AC-1-07 test/e2e: TestEnable/enable creates a restricted namespace")

    def test_renaming_a_listed_subtest_fails_naming_it(self):
        self.replace(E2E_TEST, "enable creates", "enabling creates")
        self.assert_fails_naming(self.guard(), "deleted or renamed: AC-1-07")

    def test_renaming_a_listed_function_fails_naming_it(self):
        self.replace(E2E_TEST, "func TestBlockATool(", "func TestBlock(")
        self.assert_fails_naming(self.guard(), "deleted or renamed: AC-1-25 test/e2e: TestBlockATool")

    def test_deleting_a_listed_test_file_fails(self):
        (self.repository / UNIT_TEST).unlink()
        self.assert_fails_naming(self.guard(), "AC-1-26 internal/policy: TestRules")

    def test_commenting_out_a_subtest_fails(self):
        self.replace(E2E_TEST, '\tt.Run("enable creates', '\t/* t.Run("enable creates')
        self.replace(E2E_TEST, "requireNamespace(t)\n\t})\n", "requireNamespace(t)\n\t}) */\n")
        self.assert_fails_naming(self.guard(), "deleted or renamed: AC-1-07")

    def test_line_commenting_a_listed_function_fails(self):
        self.replace(E2E_TEST, "func TestBlockATool(t *testing.T) {\n\tblock(t)\n}\n",
                     "// func TestBlockATool(t *testing.T) {\n// \tblock(t)\n// }\n")
        self.assert_fails_naming(self.guard(), "TestBlockATool")

    def test_taking_a_test_off_its_tests_line_fails(self):
        self.replace(CHECKLIST, "  Tests: `test/e2e: TestBlockATool`\n", "")
        self.assert_fails_naming(self.guard(), "removed from the Tests line: AC-1-25 test/e2e: TestBlockATool")

    # Newly skipped scenario tests.

    def test_a_new_t_skip_in_a_subtest_fails(self):
        self.replace(E2E_TEST, "requireNamespace(t)", 't.Skip("flaky")\n\t\trequireNamespace(t)')
        self.assert_fails_naming(self.guard(), "new skip call: AC-1-07 test/e2e: TestEnable/enable creates a restricted namespace")

    def test_a_new_t_skip_before_a_subtest_in_its_parent_fails(self):
        self.replace(E2E_TEST, "\tt.Parallel()\n", '\tt.Parallel()\n\tt.Skipf("later")\n')
        self.assert_fails_naming(self.guard(), "AC-1-07", "AC-1-11")

    def test_a_new_skip_in_a_listed_function_fails(self):
        self.replace(E2E_TEST, "\tblock(t)", "\tt.SkipNow()\n\tblock(t)")
        self.assert_fails_naming(self.guard(), "TestBlockATool")

    def test_a_skip_on_a_suite_variable_fails(self):
        self.replace(UNIT_TEST, "check(t, test)", "s.T().Skip()\n\t\t\tcheck(t, test)")
        self.assert_fails_naming(self.guard(), "AC-1-26")

    # The owner's override.

    def test_the_approval_label_lets_a_deletion_pass(self):
        (self.repository / UNIT_TEST).unlink()
        self.assert_passes(self.guard(labels="area:policy,test-removal-approved"))

    def test_another_label_does_not(self):
        (self.repository / UNIT_TEST).unlink()
        self.assert_fails_naming(self.guard(labels="test-removal-approved-not,area:policy"), "AC-1-26")


if __name__ == "__main__":
    unittest.main()
