#!/usr/bin/env python3
"""Tests scripts/ci/measure-ci.py's timing of check suites and its summary,
on check suite and check run objects shaped like the GitHub API's."""

import importlib.util
import pathlib
import subprocess
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).resolve().parent / "measure-ci.py"
spec = importlib.util.spec_from_file_location("measure_ci", SCRIPT)
measure_ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure_ci)

SUITE = {"id": 1, "created_at": "2026-11-17T10:00:00Z"}


def run(name, started, completed, conclusion="success", status="completed"):
    return {
        "name": name,
        "status": status,
        "conclusion": conclusion,
        "started_at": f"2026-11-17T{started}Z",
        "completed_at": f"2026-11-17T{completed}Z" if completed else None,
    }


class MeasureSuiteTest(unittest.TestCase):
    def test_wall_clock_runs_from_suite_creation_to_the_last_completion(self):
        measured = measure_ci.measure_suite(
            SUITE,
            [run("lint", "10:01:00", "10:03:00"), run("e2e", "10:00:30", "10:09:30")],
        )
        self.assertAlmostEqual(measured["wall"], 9.5)
        self.assertAlmostEqual(measured["queue"], 0.5)
        self.assertAlmostEqual(measured["stages"]["e2e"], 9.0)
        self.assertAlmostEqual(measured["stages"]["lint"], 2.0)

    def test_skipped_runs_pass_but_have_no_stage_time(self):
        measured = measure_ci.measure_suite(
            SUITE,
            [run("docs", "10:01:00", "10:01:00", "skipped"), run("unit", "10:01:00", "10:04:00")],
        )
        self.assertIsNotNone(measured)
        self.assertNotIn("docs", measured["stages"])

    def test_a_failed_or_unfinished_suite_is_not_measured(self):
        self.assertIsNone(
            measure_ci.measure_suite(SUITE, [run("unit", "10:01:00", "10:04:00", "failure")])
        )
        self.assertIsNone(
            measure_ci.measure_suite(
                SUITE, [run("unit", "10:01:00", None, None, status="in_progress")]
            )
        )

    def test_require_keeps_only_suites_where_that_run_succeeded(self):
        runs = [run("unit", "10:01:00", "10:04:00"), run("e2e", "10:01:00", "10:01:00", "skipped")]
        self.assertIsNone(measure_ci.measure_suite(SUITE, runs, require="e2e"))
        runs[1] = run("e2e", "10:01:00", "10:08:00")
        self.assertIsNotNone(measure_ci.measure_suite(SUITE, runs, require="e2e"))

    def test_excluded_runs_are_left_out_of_the_wall_clock(self):
        measured = measure_ci.measure_suite(
            SUITE,
            [run("unit", "10:01:00", "10:04:00"), run("checks", "10:05:00", "10:06:00")],
            exclude="checks",
        )
        self.assertAlmostEqual(measured["wall"], 4.0)
        self.assertNotIn("checks", measured["stages"])

    def test_a_run_started_before_its_suite_has_no_negative_queue(self):
        measured = measure_ci.measure_suite(SUITE, [run("unit", "09:59:00", "10:04:00")])
        self.assertEqual(measured["queue"], 0.0)


class PercentileTest(unittest.TestCase):
    def test_nearest_rank(self):
        values = list(range(1, 11))
        self.assertEqual(measure_ci.percentile(values, 0.5), 5)
        self.assertEqual(measure_ci.percentile(values, 0.9), 9)
        self.assertEqual(measure_ci.percentile(values, 1.0), 10)
        self.assertEqual(measure_ci.percentile([7], 0.9), 7)
        self.assertEqual(measure_ci.percentile([1, 2, 3], 0.5), 2)
        self.assertIsNone(measure_ci.percentile([], 0.5))

    def test_summary_counts_each_stage_where_it_ran(self):
        summary = measure_ci.summarize(
            [
                {"wall": 9.0, "queue": 0.1, "stages": {"e2e": 8.0, "unit": 3.0}},
                {"wall": 4.0, "queue": 0.2, "stages": {"unit": 3.5}},
            ]
        )
        self.assertEqual(summary["wall"]["n"], 2)
        self.assertEqual(summary["wall"]["max"], 9.0)
        self.assertEqual(summary["stages"]["e2e"]["n"], 1)
        self.assertEqual(summary["stages"]["unit"]["n"], 2)


class GhApiTest(unittest.TestCase):
    def completed(self, code, out=""):
        return subprocess.CompletedProcess(["gh"], code, stdout=out, stderr="")

    def test_a_transient_failure_is_retried(self):
        results = [self.completed(1), self.completed(0, '{"ok": true}')]
        with mock.patch.object(measure_ci.subprocess, "run", side_effect=results), \
                mock.patch.object(measure_ci.time, "sleep"):
            self.assertEqual(measure_ci.gh_api("x"), {"ok": True})

    def test_a_persistent_failure_is_raised(self):
        with mock.patch.object(
            measure_ci.subprocess, "run", return_value=self.completed(1)
        ), mock.patch.object(measure_ci.time, "sleep"):
            with self.assertRaises(subprocess.CalledProcessError):
                measure_ci.gh_api("x")


if __name__ == "__main__":
    unittest.main()
