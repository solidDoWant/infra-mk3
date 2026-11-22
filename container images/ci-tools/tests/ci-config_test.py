#!/usr/bin/env python3
"""Tests bin/ci-config: ci.yaml checking, defaults and stage selection."""
import importlib.machinery
import importlib.util
import os
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "bin" / "ci-config"
loader = importlib.machinery.SourceFileLoader("ci_config", str(SCRIPT))
spec = importlib.util.spec_from_loader("ci_config", loader)
ci_config = importlib.util.module_from_spec(spec)
loader.exec_module(ci_config)

BASE = """
version: 1
not-code: ["*.md", "docs/**"]
stages:
  lint:
    run: make lint
  unit:
    run: make test
  e2e:
    run: make test-e2e
    kind: true
    with: ./test/e2e/build-images.sh
  docs:
    run: make docs-check
    run-pull-request: make docs-check || true
    paths: ["**/*.md", "docs/**"]
  slow:
    run: make slow
    push: false
"""


def load(text):
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as f:
        f.write(text)
    try:
        return ci_config.load(f.name)
    finally:
        os.unlink(f.name)


class Checking(unittest.TestCase):
    def assertInvalid(self, text, fragment):
        with self.assertRaises(ci_config.Invalid) as raised:
            load(text)
        self.assertIn(fragment, str(raised.exception))

    def test_a_minimal_file_gets_its_defaults(self):
        config = load("version: 1\nstages:\n  unit:\n    run: make test\n")
        self.assertEqual(config["stages"]["unit"], {
            "run": "make test", "run-pull-request": None, "paths": None, "push": True,
            "own-tree": False, "kind": False, "with": None,
        })
        self.assertEqual(config["env"], {})
        self.assertIsNone(config["release"])
        self.assertFalse(config["test-guard"])

    def test_the_version_must_be_1(self):
        self.assertInvalid("version: 2\nstages:\n  a:\n    run: x\n", "version: must be 1")

    def test_unknown_keys_are_refused(self):
        self.assertInvalid("version: 1\nstagez: {}\n", "unknown keys ['stagez']")
        self.assertInvalid("version: 1\nstages:\n  a:\n    run: x\n    runn: y\n", "stages.a: unknown keys ['runn']")

    def test_a_stage_needs_a_command(self):
        self.assertInvalid("version: 1\nstages:\n  a:\n    kind: true\n", "stages.a.run")

    def test_reserved_and_bad_stage_names_are_refused(self):
        self.assertInvalid("version: 1\nstages:\n  release:\n    run: x\n", "`release` is reserved")
        self.assertInvalid("version: 1\nstages:\n  Bad_Name:\n    run: x\n", "lower-case")

    def test_env_names_are_checked(self):
        self.assertInvalid("version: 1\nenv:\n  lower: x\nstages:\n  a:\n    run: x\n", "upper-case")
        self.assertInvalid("version: 1\nenv:\n  CI_REPO: x\nstages:\n  a:\n    run: x\n", "ci-tools' own")
        config = load("version: 1\nenv:\n  E2E_DISCARD: true\nstages:\n  a:\n    run: x\n")
        self.assertEqual(config["env"], {"E2E_DISCARD": "true"})

    def test_image_inputs_stay_inside_the_repository(self):
        self.assertInvalid("version: 1\nimage:\n  inputs:\n    - path: ../x\nstages:\n  a:\n    run: x\n", "inside the repository")
        self.assertInvalid("version: 1\nimage:\n  inputs:\n    - path: go.mod\n      lines: '('\nstages:\n  a:\n    run: x\n", "regular expression")

    def test_release_rules(self):
        stages = "stages:\n  a:\n    run: x\n"
        self.assertInvalid("version: 1\n" + stages + "release: {}\n", "publishes nothing")
        self.assertInvalid("version: 1\n" + stages + "release:\n  charts: [c]\n", "release.chart-registry")
        self.assertInvalid("version: 1\n" + stages + "release:\n  charts: [c]\n  chart-registry: ghcr.io/x\n", "oci://")
        self.assertInvalid("version: 1\n" + stages + "release:\n  images: [ghcr.io/x/y]\n", "release.build")
        config = load("version: 1\n" + stages + "release:\n  assets: make assets\n")
        self.assertEqual(config["release"]["images"], [])

    def test_a_missing_file_is_reported(self):
        with self.assertRaises(ci_config.Invalid) as raised:
            ci_config.load("/nonexistent/ci.yaml")
        self.assertIn("every project needs a ci.yaml", str(raised.exception))


class Fixture(unittest.TestCase):
    def test_the_fixture_projects_ci_yaml_is_valid(self):
        config = ci_config.load(str(SCRIPT.parent.parent / "tests" / "fixture" / "ci.yaml"))
        self.assertEqual(list(config["stages"]), ["lint", "unit", "docs", "test-guard"])
        self.assertEqual(config["release"]["charts"], ["deploy/charts/fixture"])


class Selection(unittest.TestCase):
    def setUp(self):
        self.config = load(BASE)

    def select(self, event, files=()):
        return ci_config.select(self.config, event, list(files))

    def test_a_push_runs_every_stage_but_push_false(self):
        self.assertEqual(self.select("push"), ["lint", "unit", "e2e", "docs"])

    def test_a_release_runs_only_the_release(self):
        self.assertEqual(self.select("release"), ["release"])

    def test_a_code_change_runs_the_code_stages_and_not_docs(self):
        self.assertEqual(self.select("pull_request", ["cmd/x/main.go"]), ["lint", "unit", "e2e", "slow"])

    def test_a_docs_only_change_runs_only_docs(self):
        self.assertEqual(self.select("pull_request", ["README.md", "docs/a/b.md"]), ["docs"])

    def test_a_mixed_change_runs_both(self):
        self.assertEqual(self.select("pull_request", ["go.mod", "docs/x.md"]), ["lint", "unit", "e2e", "docs", "slow"])

    def test_no_change_runs_nothing(self):
        self.assertEqual(self.select("pull_request", []), [])

    def test_the_test_guard_runs_on_every_pull_request_change_only(self):
        config = load(BASE + "test-guard: true\n")
        self.assertIn("make test-guard", config["stages"]["test-guard"]["run"])
        self.assertIn("CI_PR_LABELS", config["stages"]["test-guard"]["run"])
        self.assertIn("test-guard", ci_config.select(config, "pull_request", ["README.md"]))
        self.assertIn("test-guard", ci_config.select(config, "pull_request", ["go.mod"]))
        self.assertNotIn("test-guard", ci_config.select(config, "push", []))
        self.assertEqual(ci_config.select(config, "pull_request", []), [])

    def test_star_stays_inside_one_segment(self):
        self.assertTrue(ci_config.matches("README.md", ["*.md"]))
        self.assertFalse(ci_config.matches("docs/README.md", ["*.md"]))
        self.assertTrue(ci_config.matches("docs/a/README.md", ["**/*.md"]))
        self.assertTrue(ci_config.matches(".github/x.md", ["**/*.md"]))


if __name__ == "__main__":
    unittest.main()
