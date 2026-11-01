"""Backfill sub-issue parents: follow-ups under the issue they came from when
that issue is in the same milestone, everything else under its milestone's epic. Usage: backfill_parents.py REPO [--apply]"""
import json, re, subprocess, sys
REPO = sys.argv[1]; APPLY = "--apply" in sys.argv
owner, name = REPO.split("/")

def gh(*a):
    r = subprocess.run(["gh", *a], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr.strip())
    return r.stdout

q = '''query($o:String!,$n:String!,$c:String){repository(owner:$o,name:$n){issuesAndPrs: issues(first:100,after:$c){pageInfo{hasNextPage endCursor}
 nodes{number id databaseId title body state milestone{title} parent{number} subIssues{totalCount} labels(first:30){nodes{name}}}}}}'''
issues, cursor = {}, None
while True:
    args = ["api","graphql","-f",f"query={q}","-F",f"o={owner}","-F",f"n={name}"] + (["-F",f"c={cursor}"] if cursor else [])
    d = json.loads(gh(*args))["data"]["repository"]["issuesAndPrs"]
    for n in d["nodes"]: issues[n["number"]] = n
    if not d["pageInfo"]["hasNextPage"]: break
    cursor = d["pageInfo"]["endCursor"]

prq = '''query($o:String!,$n:String!,$c:String){repository(owner:$o,name:$n){pullRequests(first:100,after:$c,states:[OPEN,MERGED,CLOSED]){pageInfo{hasNextPage endCursor}
 nodes{number closingIssuesReferences(first:5){nodes{number}}}}}}'''
pr_issue, cursor = {}, None
while True:
    args = ["api","graphql","-f",f"query={prq}","-F",f"o={owner}","-F",f"n={name}"] + (["-F",f"c={cursor}"] if cursor else [])
    d = json.loads(gh(*args))["data"]["repository"]["pullRequests"]
    for p in d["nodes"]:
        refs = [x["number"] for x in p["closingIssuesReferences"]["nodes"]]
        if refs: pr_issue[p["number"]] = refs[0]
    if not d["pageInfo"]["hasNextPage"]: break
    cursor = d["pageInfo"]["endCursor"]

labels = lambda i: {l["name"] for l in i["labels"]["nodes"]}
epic = {i["milestone"]["title"]: i for i in issues.values() if "epic" in labels(i) and i["milestone"]}
children = {e["number"]: e["subIssues"]["totalCount"] for e in epic.values()}

def origin(i):
    head = (i["body"] or "")[:400]
    for num in map(int, re.findall(r"#(\d+)", head)):
        if num == i["number"]: continue
        if num in issues and "epic" not in labels(issues[num]): return num
        if num in pr_issue and pr_issue[num] != i["number"]: return pr_issue[num]
    return None

plan, unmatched = [], []
for i in sorted(issues.values(), key=lambda x: x["number"]):
    if "epic" in labels(i) or i["parent"] or not i["milestone"]: continue
    if i["title"].startswith("pm:"): continue
    parent = None
    if "follow-up" in labels(i) or re.match(r"(follow-up|non-blocking|split from)", (i["body"] or "").strip(), re.I) or re.search(r"follow-ups? from|review of", (i["body"] or "")[:200], re.I):
        parent = origin(i)
        # A parent must be in the issue's own milestone, so epics show exactly their phase.
        if parent and (issues.get(parent) or {}).get("milestone") != i["milestone"]:
            parent = None
    why = "origin"
    if parent is None:
        e = epic.get(i["milestone"]["title"])
        if not e: unmatched.append((i["number"], "no epic for milestone")); continue
        if children[e["number"]] >= 100: unmatched.append((i["number"], f"epic #{e['number']} full")); continue
        parent, why = e["number"], "epic"
        children[e["number"]] += 1
    plan.append((i["number"], parent, why))

print(f"{len(plan)} links planned ({sum(1 for p in plan if p[2]=='origin')} to origin issue, {sum(1 for p in plan if p[2]=='epic')} to phase epic); {len(unmatched)} unmatched")
for c, p, w in plan[:8]: print(f"  #{c} -> #{p} ({w})")
for u in unmatched: print("  UNMATCHED", u)
print("epic child counts after:", children)
if APPLY:
    failed = 0
    for c, p, _ in plan:
        r = subprocess.run(["gh","api",f"repos/{REPO}/issues/{p}/sub_issues","--method","POST","-F",f"sub_issue_id={issues[c]['databaseId']}"], capture_output=True, text=True)
        if r.returncode: failed += 1; print(f"  FAIL #{c} -> #{p}: {r.stderr.strip()[:150]}")
    print(f"applied {len(plan)-failed}/{len(plan)}")
