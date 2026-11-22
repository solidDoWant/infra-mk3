#!/usr/bin/env python3
"""Summarises the CI stages that scripts/ci/stages.sh ran on Tekton.

Reads each stage's files in the output directory (`<stage>.exit`, `.start`,
`.end`, `.log` and the optional `.stats` with `memory_peak` bytes and
`usage_usec` CPU time), prints a table of results, times, peak memory and CPU
use, and writes the summary as JSON for the report task: a list with each
stage's name, result, start and end time, and for a failed stage a short
failure report. Tekton hands the result over inside the step's termination
message, as a JSON string in Tekton's own JSON. Kubernetes cuts that message
to a share of the pod's 12 KiB budget for termination messages, which the
step shares with the sidecar and Tekton's init containers. A cut message
loses the result, and the report task is then skipped. So the result is
measured as it is encoded there and fits in RESULT_LIMIT, well inside the
smallest share; the failure reports are cut to share what is left.

    stages-report.py OUT_DIR SUMMARY_JSON STAGE...
"""

import json
import pathlib
import sys

RESULT_LIMIT = 2048
# Lines that locate a Go test failure.
FAILURE_MARKERS = ("--- FAIL:", "Error Trace:", "FAIL\t", "panic:")
TAIL_LINES = 20
CUT = "\n[...]\n"


def read(path, default=""):
    try:
        return path.read_text(errors="replace").strip()
    except FileNotFoundError:
        return default


def failure_report(log):
    """The failure lines of a stage log, then its last lines."""
    lines = log.splitlines()
    markers = [line.strip() for line in lines if any(marker in line for marker in FAILURE_MARKERS)]
    tail = lines[-TAIL_LINES:]
    parts = []
    if markers:
        parts.append("\n".join(markers))
    parts.append("\n".join(tail))
    return "\n---\n".join(parts)


def cut(text, limit):
    """Cuts text to at most limit characters, keeping its start and its end."""
    if len(text) <= limit:
        return text
    if limit <= len(CUT):
        return text[:max(limit, 0)]
    keep = limit - len(CUT)
    head = keep // 2
    return text[:head] + CUT + text[len(text) - (keep - head):]


def stage_summary(out, name):
    exit_code = read(out / f"{name}.exit")
    start = read(out / f"{name}.start", "0")
    end = read(out / f"{name}.end", start)
    stats = dict(line.split()[:2] for line in read(out / f"{name}.stats").splitlines() if len(line.split()) >= 2)
    summary = {
        "name": name,
        "result": "passed" if exit_code == "0" else "failed",
        "started": int(start),
        "ended": int(end),
        "seconds": int(end) - int(start),
        "memory_peak_bytes": int(stats.get("memory_peak", 0)),
        "cpu_seconds": round(int(stats.get("usage_usec", 0)) / 1e6, 1),
    }
    if summary["result"] == "failed":
        summary["report"] = failure_report(read(out / f"{name}.log"))
    return summary


def fit(summaries, limit=RESULT_LIMIT):
    """Cuts the failure reports so that the JSON of summaries fits in limit
    bytes. Every failed stage gets an equal share of the space left."""
    failed = [s for s in summaries if "report" in s]
    if not failed:
        return summaries
    reports = {s["name"]: s["report"] for s in failed}
    for s in failed:
        s["report"] = ""
    left = limit - wrapped_length(encode(summaries))
    share = left // len(failed)
    for s in failed:
        # Two layers of JSON escapes make a report longer than its text:
        # find the longest cut whose encoding fits the share.
        report = reports[s["name"]]
        low, high = 0, len(report)
        while low < high:
            middle = (low + high + 1) // 2
            if escaped_length(cut(report, middle)) <= share:
                low = middle
            else:
                high = middle - 1
        s["report"] = cut(report, low)
    return summaries


def escaped_length(text):
    """The length of text inside the result once the result is a string in
    the termination message. Escaping works on each character alone, so the
    lengths of the parts add up."""
    return wrapped_length(json.dumps(text)[1:-1])


def wrapped_length(text):
    return len(json.dumps(text)) - 2


def encode(summaries):
    return json.dumps(summaries, separators=(",", ":"))


def table(summaries):
    rows = ["stage        result  time    peak memory  CPU (cores)"]
    for s in summaries:
        cores = s["cpu_seconds"] / s["seconds"] if s["seconds"] else 0
        memory = f"{s['memory_peak_bytes'] / 2**30:.1f} GiB" if s["memory_peak_bytes"] else "-"
        rows.append(f"{s['name']:<12} {s['result']:<7} {s['seconds']:>4}s  {memory:>11}  {cores:>4.1f}")
    return "\n".join(rows)


def main(argv):
    if len(argv) < 3:
        print("usage: stages-report.py OUT_DIR SUMMARY_JSON STAGE...", file=sys.stderr)
        return 2
    out = pathlib.Path(argv[1])
    summaries = fit([stage_summary(out, name) for name in argv[3:]])
    pathlib.Path(argv[2]).write_text(encode(summaries))
    print(table(summaries))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
