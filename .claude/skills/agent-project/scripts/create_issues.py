"""Create labels, milestones, phase epics, sub-issues, and blocked-by links.

Usage: create_issues.py OWNER/REPO path/to/issues.py STATE.json

issues.py defines PHASES {n: (title, description)} and ISSUES (see
issues_example.py). STATE.json records what was created so the script is
idempotent: re-run it after a failure and it resumes.
"""
import importlib.util, json, subprocess, sys, os
REPO, DATA, STATE = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location("issues_data", DATA)
data = importlib.util.module_from_spec(spec); spec.loader.exec_module(data)
ISSUES, PHASES = data.ISSUES, data.PHASES
created = json.load(open(STATE)) if os.path.exists(STATE) else {}

def gh(*args, input=None):
    r = subprocess.run(["gh", *args], capture_output=True, text=True, input=input)
    if r.returncode != 0:
        raise SystemExit(f"gh {args[:3]} failed: {r.stderr}")
    return r.stdout

def save(): json.dump(created, open(STATE, "w"), indent=1)

LABELS = {
 "status:triage": "ededed", "follow-up": "c5def5", "status:todo": "ededed", "status:in-progress": "fbca04", "status:in-review": "0e8a16", "status:blocked": "b60205",
 "status:decomposed": "c5def5", "needs-human": "d93f0b", "epic": "3e4b9e", "bughunt": "5319e7", "security": "b60205",
 "question": "d876e3", "bug": "d73a4a", "severity:critical": "b60205", "severity:high": "d93f0b",
 "severity:medium": "fbca04", "severity:low": "c2e0c6", "pm:status": "1d76db", "pm:decisions": "1d76db",
 "area:server": "bfdadc", "area:plugin": "bfdadc", "area:proto": "bfdadc", "area:sim": "bfdadc",
 "area:crypto": "bfdadc", "area:ops": "bfdadc",
}
for p in PHASES: LABELS[f"phase:{p}"] = "0052cc"
existing = {l["name"] for l in json.loads(gh("label", "list", "-R", REPO, "--limit", "200", "--json", "name"))}
for name, color in LABELS.items():
    if name not in existing:
        gh("label", "create", name, "-R", REPO, "--color", color)

ms = {m["title"]: m["number"] for m in json.loads(gh("api", f"repos/{REPO}/milestones?state=all"))}
for p, (title, desc) in PHASES.items():
    if title not in ms:
        ms[title] = json.loads(gh("api", f"repos/{REPO}/milestones", "-f", f"title={title}", "-f", f"description={desc}"))["number"]

def create(key, title, body, labels, milestone):
    if key in created: return created[key]
    args = ["api", f"repos/{REPO}/issues", "-f", f"title={title}", "-f", f"body={body}"]
    for l in labels: args += ["-f", f"labels[]={l}"]
    if milestone: args += ["-F", f"milestone={milestone}"]
    out = json.loads(gh(*args))
    created[key] = {"number": out["number"], "id": out["id"]}
    save(); print(key, out["number"], flush=True)
    return created[key]

# Epics
for p, (title, desc) in PHASES.items():
    body = (f"## Summary\n\n{desc}\n\nThis is the parent issue for {title}. Its sub-issues are the work items; the project manager decomposes them further when needed (see `docs/agents/project-manager.md`).\n\n"
            "## Acceptance Criteria\n\n- [ ] **Given** every sub-issue is closed or explicitly deferred on the decision log, **when** the phase-end bug hunt"
            + (" and security review" if p in (1,2,3,4,5) else "") + " have run, **then** no critical or high findings remain open and a phase summary is posted on the PM status issue.\n\n"
            "## Non-Goals\n\n- Work belonging to later phases.\n")
    create(f"epic{p}", f"epic: {title}", body, ["epic", f"phase:{p}"], ms[title])

order, seen = [], set()
byk = {i["key"]: i for i in ISSUES}
def visit(i):
    if i["key"] in seen: return
    seen.add(i["key"])
    for d in i["deps"]: visit(byk[d])
    order.append(i)
for i in ISSUES: visit(i)
for it in order:
    deps = [f"#{created[d]['number']}" for d in it["deps"]]
    body = it["body"].replace("{deps}", ", ".join(deps) if deps else "none")
    labels = it["labels"] + [f"phase:{it['phase']}"] + ([] if "needs-human" in it["labels"] else ["status:todo"])
    create(it["key"], it["title"], body, labels, ms[PHASES[it["phase"]][0]])

# sub-issue + dependency links
links = created.setdefault("_links", [])
for it in ISSUES:
    child = created[it["key"]]; parent = created[f"epic{it['phase']}"]
    tag = f"sub:{it['key']}"
    if tag not in links:
        gh("api", f"repos/{REPO}/issues/{parent['number']}/sub_issues", "--method", "POST", "-F", f"sub_issue_id={child['id']}")
        links.append(tag); save()
    for d in it["deps"]:
        tag = f"dep:{it['key']}<-{d}"
        if tag not in links:
            gh("api", f"repos/{REPO}/issues/{child['number']}/dependencies/blocked_by", "--method", "POST", "-F", f"issue_id={created[d]['id']}")
            links.append(tag); save()
# epics blocked by previous epic
for p in list(PHASES)[1:]:
    tag = f"epicdep:{p}"
    if tag not in links:
        gh("api", f"repos/{REPO}/issues/{created[f'epic{p}']['number']}/dependencies/blocked_by", "--method", "POST", "-F", f"issue_id={created[f'epic{p-1}']['id']}")
        links.append(tag); save()
print("done")
