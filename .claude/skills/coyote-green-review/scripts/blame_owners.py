#!/usr/bin/env python3
"""Find which team's PRs introduced the lines a PR modifies or deletes.

Usage: blame_owners.py <repo-clone-dir> <base-ref> <pr.diff> [owner/repo]

For every line removed or changed in the diff, runs `git blame` on the base ref,
maps each blamed commit to the PR that introduced it (via `gh api`), and prints
the ones whose PR title has a non-GT ticket prefix (PT-, EP-, OT-, ...).
Output is grouped by file so a reviewer can say "this came from purple team's PT-1234".
"""
import json
import re
import subprocess
import sys
from collections import defaultdict

repo_dir, base_ref, diff_path = sys.argv[1:4]
gh_repo = sys.argv[4] if len(sys.argv) > 4 else "RoadRunnerEngineering/coyote"

# Parse old-side line numbers of removed lines per file
removed = defaultdict(list)
cur_file = None
old_line = 0
with open(diff_path) as f:
    for line in f:
        if line.startswith("--- "):
            path = line[4:].strip()
            cur_file = None if path == "/dev/null" else path[2:] if path.startswith("a/") else path
        elif line.startswith("+++ "):
            continue
        elif line.startswith("@@"):
            m = re.match(r"@@ -(\d+)(?:,\d+)? \+", line)
            old_line = int(m.group(1)) if m else 0
        elif cur_file is None:
            continue
        elif line.startswith("-"):
            removed[cur_file].append(old_line)
            old_line += 1
        elif line.startswith("+"):
            continue
        else:
            old_line += 1

import os
SHOW_ALL = os.environ.get("SHOW_ALL") == "1"
pr_cache = {}


def pr_for(sha):
    if sha in pr_cache:
        return pr_cache[sha]
    try:
        out = subprocess.run(
            ["gh", "api", f"repos/{gh_repo}/commits/{sha}/pulls", "--jq",
             '.[0] | "\\(.number)\\t\\(.title)"'],
            capture_output=True, text=True, timeout=30,
        ).stdout.strip()
    except subprocess.TimeoutExpired:
        out = ""
    pr_cache[sha] = out
    return out


results = defaultdict(lambda: defaultdict(list))  # file -> (pr, date) -> lines
for path, lines in removed.items():
    if not lines:
        continue
    args = ["git", "-C", repo_dir, "blame", "--line-porcelain", base_ref]
    for ln in lines:
        args += ["-L", f"{ln},{ln}"]
    args += ["--", path]
    proc = subprocess.run(args, capture_output=True, text=True)
    if proc.returncode != 0:
        continue
    sha = date = None
    idx = 0
    for bl in proc.stdout.splitlines():
        if re.match(r"^[0-9a-f]{40} ", bl):
            sha = bl.split()[0]
        elif bl.startswith("committer-time "):
            import datetime
            date = datetime.datetime.utcfromtimestamp(int(bl.split()[1])).date().isoformat()
        elif bl.startswith("\t"):
            pr = pr_for(sha)
            results[path][(pr, date, sha[:8])].append(lines[idx] if idx < len(lines) else "?")
            idx += 1

found = False
for path, groups in results.items():
    for (pr, date, sha), lns in sorted(groups.items(), key=lambda kv: kv[0][1] or "", reverse=True):
        title = pr.split("\t", 1)[1] if "\t" in pr else ""
        m = re.search(r"\b([A-Z]{2,4})-\d+", title)
        prefix = m.group(1) if m else "?"
        if prefix == "GT" and not SHOW_ALL:
            continue
        found = True
        print(f"{path} lines {min(lns)}-{max(lns)} ({len(lns)}): {date} {sha} PR #{pr.split(chr(9))[0] or '?'} [{prefix}] {title}")

if not found:
    print("No modified/deleted lines trace back to non-GT PRs.")
