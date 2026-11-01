"""Make every issue's sub-issue parent live in the issue's own milestone:
keep a parent in the same milestone, otherwise use the milestone's epic.
Usage: reparent_by_milestone.py OWNER/REPO [--apply]"""
import json, subprocess, sys
REPO = sys.argv[1]; APPLY = "--apply" in sys.argv
owner, name = REPO.split("/")
def gh(*a):
    r = subprocess.run(["gh", *a], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr.strip())
    return r.stdout
q = '''query($o:String!,$n:String!,$c:String){repository(owner:$o,name:$n){issues(first:100,after:$c){pageInfo{hasNextPage endCursor}
 nodes{number databaseId title milestone{title} parent{number milestone{title}} subIssues{totalCount} labels(first:30){nodes{name}}}}}}'''
issues, c = {}, None
while True:
    a = ["api","graphql","-f",f"query={q}","-F",f"o={owner}","-F",f"n={name}"] + (["-F",f"c={c}"] if c else [])
    d = json.loads(gh(*a))["data"]["repository"]["issues"]
    for n in d["nodes"]: issues[n["number"]] = n
    if not d["pageInfo"]["hasNextPage"]: break
    c = d["pageInfo"]["endCursor"]
is_epic = lambda i: any(l["name"] == "epic" for l in i["labels"]["nodes"])
epic = {i["milestone"]["title"]: i for i in issues.values() if is_epic(i) and i["milestone"]}
count = {e["number"]: e["subIssues"]["totalCount"] for e in epic.values()}
plan, problems = [], []
for i in sorted(issues.values(), key=lambda x: x["number"]):
    if is_epic(i) or not i["milestone"] or i["title"].startswith("pm:"): continue
    m = i["milestone"]["title"]; p = i["parent"]
    if p and p["milestone"] and p["milestone"]["title"] == m: continue
    e = epic.get(m)
    if not e: problems.append((i["number"], f"no epic for {m}")); continue
    if p and p["number"] == e["number"]: continue
    if count[e["number"]] >= 100: problems.append((i["number"], f"epic #{e['number']} full")); continue
    count[e["number"]] += 1
    if p: count[p["number"]] = count.get(p["number"], 0)
    plan.append((i["number"], e["number"], p["number"] if p else None))
print(f"{len(plan)} re-parents ({sum(1 for x in plan if x[2])} moved, {sum(1 for x in plan if not x[2])} orphans); problems: {problems}")
print("epic child counts after:", {k: v for k, v in count.items() if k in {e['number'] for e in epic.values()}})
if APPLY:
    bad = 0
    for child, parent, old in plan:
        args = ["api", f"repos/{REPO}/issues/{parent}/sub_issues", "--method", "POST", "-F", f"sub_issue_id={issues[child]['databaseId']}"]
        if old: args += ["-F", "replace_parent=true"]
        r = subprocess.run(["gh", *args], capture_output=True, text=True)
        if r.returncode: bad += 1; print(f"FAIL #{child}: {r.stderr.strip()[:160]}")
    print(f"applied {len(plan)-bad}/{len(plan)}")
