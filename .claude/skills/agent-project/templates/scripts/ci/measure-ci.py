#!/usr/bin/env python3
"""Measures CI wall-clock time from the GitHub check runs of recent commits.

GitHub Actions reports each job as a check run, and Pipelines-as-Code reports
each PipelineRun as a check run, both with start and end times and grouped in
a check suite per app and commit. So one measurement works for both CI
systems: for each commit and app, the suite's creation (when the push or pull
request event reached the app) to the last selected check run's completion.

Commits come from two sources, which give the event type:
  push          the default branch's commits since --since
  pull_request  the commits of pull requests updated since --since

Usage:
  measure-ci.py --app github-actions --require e2e --exclude checks
  measure-ci.py --app <pipelines-as-code app slug> --since 2026-12-01

Prints p50, p90 and max (minutes) of the wall clock, of the queue (suite
created to the first check run's start), and of each check run's own
duration, per event type. --json prints the per-suite numbers instead.
"""

import argparse
import datetime
import json
import re
import subprocess
import sys
import time


def gh_api(path, attempts=4):
    """Returns the decoded JSON of one GitHub API GET, retrying transient errors."""
    for attempt in range(attempts):
        result = subprocess.run(
            ["gh", "api", "-H", "Accept: application/vnd.github+json", path],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            return json.loads(result.stdout)
        if attempt == attempts - 1:
            raise subprocess.CalledProcessError(
                result.returncode, result.args, result.stdout, result.stderr
            )
        time.sleep(2 * (attempt + 1))


def gh_pages(path, key=None, limit=None):
    """Yields the items of a paginated list endpoint, 100 per page."""
    separator = "&" if "?" in path else "?"
    page = 1
    count = 0
    while True:
        body = gh_api(f"{path}{separator}per_page=100&page={page}")
        items = body[key] if key else body
        for item in items:
            yield item
            count += 1
            if limit is not None and count >= limit:
                return
        if len(items) < 100:
            return
        page += 1


def parse_time(value):
    """Parses a GitHub timestamp (RFC 3339, UTC) into an aware datetime."""
    if value is None:
        return None
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


def minutes(start, end):
    return (end - start).total_seconds() / 60


def percentile(values, fraction):
    """The nearest-rank percentile of values (fraction in 0..1)."""
    if not values:
        return None
    ordered = sorted(values)
    rank = max(1, -(-int(fraction * 100) * len(ordered) // 100))
    return ordered[min(rank, len(ordered)) - 1]


# Check run conclusions that count as passing: a skipped Actions job (a
# docs-only change skipping the Go tests) still lets the suite pass.
PASSING = {"success", "skipped", "neutral"}


def measure_suite(suite, runs, require=None, exclude=None):
    """The timing of one check suite, or None when it doesn't qualify.

    suite is a check suite object, runs its check runs. A suite qualifies
    when every selected run completed and passed and, with require, a run of
    that name succeeded (a suite where e2e was skipped measures something
    else). exclude is a regular expression of check run names left out, such
    as an aggregate job that only waits for the others.
    """
    selected = [
        run for run in runs if not (exclude and re.fullmatch(exclude, run["name"]))
    ]
    if not selected:
        return None
    if any(run["status"] != "completed" for run in selected):
        return None
    if any(run["conclusion"] not in PASSING for run in selected):
        return None
    if require and not any(
        run["name"] == require and run["conclusion"] == "success" for run in selected
    ):
        return None
    created = parse_time(suite["created_at"])
    started = [parse_time(run["started_at"]) for run in selected]
    completed = [parse_time(run["completed_at"]) for run in selected]
    stages = {}
    for run in selected:
        if run["conclusion"] == "success":
            stages[run["name"]] = minutes(
                parse_time(run["started_at"]), parse_time(run["completed_at"])
            )
    return {
        "created_at": suite["created_at"],
        "wall": minutes(created, max(completed)),
        "queue": max(0.0, minutes(created, min(started))),
        "stages": stages,
    }


def summarize(measurements):
    """p50, p90 and max of the wall clock, queue and each stage."""

    def stats(values):
        return {
            "n": len(values),
            "p50": percentile(values, 0.5),
            "p90": percentile(values, 0.9),
            "max": max(values) if values else None,
        }

    stage_names = sorted({name for m in measurements for name in m["stages"]})
    return {
        "wall": stats([m["wall"] for m in measurements]),
        "queue": stats([m["queue"] for m in measurements]),
        "stages": {
            name: stats([m["stages"][name] for m in measurements if name in m["stages"]])
            for name in stage_names
        },
    }


def commits(repo, branch, since, limit):
    """(event, sha) pairs: default-branch pushes and pull request commits."""
    seen = set()
    for commit in gh_pages(f"repos/{repo}/commits?sha={branch}&since={since}", limit=limit):
        seen.add(commit["sha"])
        yield "push", commit["sha"]
    since_time = parse_time(since)
    pulls = gh_pages(f"repos/{repo}/pulls?state=all&sort=updated&direction=desc&base={branch}")
    for count, pull in enumerate(pulls):
        if parse_time(pull["updated_at"]) < since_time or count >= limit:
            return
        for commit in gh_pages(f"repos/{repo}/pulls/{pull['number']}/commits"):
            if commit["sha"] not in seen:
                seen.add(commit["sha"])
                yield "pull_request", commit["sha"]


def measure_commit(repo, sha, app, require, exclude):
    """The measured suites of one commit for the app."""
    suites = {
        suite["id"]: suite
        for suite in gh_pages(f"repos/{repo}/commits/{sha}/check-suites", key="check_suites")
        if suite["app"]["slug"] == app
    }
    runs = {}
    for run in gh_pages(f"repos/{repo}/commits/{sha}/check-runs", key="check_runs"):
        if run["check_suite"]["id"] in suites:
            runs.setdefault(run["check_suite"]["id"], []).append(run)
    results = []
    for suite_id, suite_runs in runs.items():
        measured = measure_suite(suites[suite_id], suite_runs, require, exclude)
        if measured:
            results.append(measured)
    return results


def format_stats(name, stats):
    def number(value):
        return "-" if value is None else f"{value:.1f}"

    return (
        f"  {name:<24} n={stats['n']:<3} p50 {number(stats['p50'])}"
        f"  p90 {number(stats['p90'])}  max {number(stats['max'])}"
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", default="{{GH_USER}}/{{PROJECT}}")
    parser.add_argument("--branch", default="master")
    parser.add_argument(
        "--app",
        default="github-actions",
        help="slug of the app whose check runs are measured",
    )
    parser.add_argument(
        "--since",
        default=(
            datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=3)
        ).strftime("%Y-%m-%dT%H:%M:%SZ"),
        help="earliest commit or pull request update (default: 3 days ago)",
    )
    parser.add_argument("--until", help="leave out suites created after this time")
    parser.add_argument(
        "--require",
        help="count only suites in which a check run of this name succeeded",
    )
    parser.add_argument(
        "--exclude",
        help="regular expression of check run names to leave out",
    )
    parser.add_argument("--limit", type=int, default=100, help="commits and pull requests read per source")
    parser.add_argument("--json", action="store_true", help="print every measured suite")
    args = parser.parse_args(argv)

    until = parse_time(args.until) if args.until else None
    by_event = {"pull_request": [], "push": []}
    for event, sha in commits(args.repo, args.branch, args.since, args.limit):
        for measured in measure_commit(args.repo, sha, args.app, args.require, args.exclude):
            if until and parse_time(measured["created_at"]) > until:
                continue
            measured["sha"] = sha
            by_event[event].append(measured)

    if args.json:
        json.dump(by_event, sys.stdout, indent=2)
        print()
        return 0
    for event, measurements in by_event.items():
        summary = summarize(measurements)
        print(f"{event} (minutes)")
        print(format_stats("wall clock", summary["wall"]))
        print(format_stats("queue", summary["queue"]))
        for name, stats in summary["stages"].items():
            print(format_stats(name, stats))
    return 0


if __name__ == "__main__":
    sys.exit(main())
