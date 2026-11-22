#!/usr/bin/env python3
"""Tests lib/stages-report.py's stage summary: results, failure
reports and the size limit of the Task result."""

import importlib.util
import json
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "lib" / "stages-report.py"
spec = importlib.util.spec_from_file_location("stages_report", SCRIPT)
stages_report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stages_report)


# The termination message the step's share of the pod's budget keeps: the
# pod has the step, the dind sidecar and Tekton's init containers.
TERMINATION_BUDGET = 2304


class StagesReportTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.out = pathlib.Path(self.dir.name)

    def tearDown(self):
        self.dir.cleanup()

    def stage(self, name, exit_code, log="", start=100, end=160, stats=None):
        if exit_code is not None:
            (self.out / f"{name}.exit").write_text(f"{exit_code}\n")
        (self.out / f"{name}.start").write_text(f"{start}\n")
        (self.out / f"{name}.end").write_text(f"{end}\n")
        (self.out / f"{name}.log").write_text(log)
        if stats:
            (self.out / f"{name}.stats").write_text(stats)

    @staticmethod
    def termination_message(raw):
        """The step's termination message as Tekton writes it, with the
        result and the step's start time."""
        return json.dumps(
            [{"key": "output", "value": raw, "type": 1},
             {"key": "StartedAt", "value": "2026-11-18T07:57:20.123Z", "type": 3}],
            separators=(",", ":"),
        ).encode()

    def run_report(self, *names):
        summary = self.out / "stages.json"
        self.assertEqual(stages_report.main(["stages-report.py", str(self.out), str(summary), *names]), 0)
        raw = summary.read_text()
        return raw, json.loads(raw)

    def test_a_stage_that_exited_zero_passed_with_its_time_and_use(self):
        self.stage("lint", 0, stats="memory_peak 2147483648\nusage_usec 30000000\n")
        _, summaries = self.run_report("lint")
        self.assertEqual(
            summaries,
            [{"name": "lint", "result": "passed", "started": 100, "ended": 160, "seconds": 60,
              "memory_peak_bytes": 2147483648, "cpu_seconds": 30.0}],
        )

    def test_a_stage_that_exited_non_zero_failed_with_its_failure_lines_and_tail(self):
        log = "ok  a\n--- FAIL: TestPush (0.1s)\n    Error Trace: push_test.go:12\n" + "".join(f"line {n}\n" for n in range(40))
        self.stage("unit", 2, log=log)
        _, summaries = self.run_report("unit")
        report = summaries[0]["report"]
        self.assertEqual(summaries[0]["result"], "failed")
        self.assertIn("--- FAIL: TestPush (0.1s)", report)
        self.assertIn("Error Trace: push_test.go:12", report)
        self.assertIn("line 39", report)
        self.assertNotIn("line 19\n", report)

    def test_a_stage_without_an_exit_status_failed(self):
        self.stage("e2e", None)
        _, summaries = self.run_report("e2e")
        self.assertEqual(summaries[0]["result"], "failed")

    def test_the_summary_fits_the_task_result_limit_with_long_failure_logs(self):
        long_line = "x\"\\é" * 400
        for name in ("lint", "unit", "e2e"):
            self.stage(name, 1, log="\n".join(f"--- FAIL: Test{n} {long_line}" for n in range(30)))
        self.stage("docs", 0)
        raw, summaries = self.run_report("lint", "unit", "e2e", "docs")
        self.assertLessEqual(len(self.termination_message(raw)), TERMINATION_BUDGET)
        for summary in summaries[:3]:
            self.assertTrue(summary["report"].startswith("--- FAIL: Test0"))
            self.assertIn("[...]", summary["report"])

    def test_a_go_test_failure_report_fits_the_termination_message(self):
        log = "".join(f"ok  \tgithub.com/x/pkg{n}\t1.0s\n" for n in range(60))
        log += "--- FAIL: TestA (0.00s)\n    a_test.go:6: \"quoted\" failure\nFAIL\tgithub.com/x/pkg\t1.0s\n" * 20
        for name in ("unit", "generate"):
            self.stage(name, 2, log=log)
        self.stage("lint", 0)
        raw, summaries = self.run_report("lint", "unit", "generate")
        self.assertLessEqual(len(self.termination_message(raw)), TERMINATION_BUDGET)
        self.assertIn("--- FAIL: TestA", summaries[1]["report"])

    def test_the_failure_reports_use_the_space_left(self):
        self.stage("unit", 1, log="--- FAIL: TestA\n" + "y" * 10000)
        raw, _ = self.run_report("unit")
        self.assertGreater(len(self.termination_message(raw)), TERMINATION_BUDGET - 512)


if __name__ == "__main__":
    unittest.main()
