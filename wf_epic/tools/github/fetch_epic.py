#!/usr/bin/env python3
"""
Fetch a GitHub issue acting as an epic, plus its sub-issues.

GitHub has no group-level epic. The epic IS an ordinary issue, and its children
are native sub-issues:
    khai-nguyen-quang/dash-cam#1  ->  https://github.com/khai-nguyen-quang/dash-cam/issues/1

Sub-issues may live in a different repository from their parent, so scope is
derived from the children rather than assumed to be the parent's repo.

Usage:
    fetch_epic.py owner/repo#1              # description + children
    fetch_epic.py owner/repo#1 --json
    fetch_epic.py owner/repo#1 --refs-only  # child refs, one per line, for the seed script
    fetch_epic.py owner/repo#1 --detail     # children + the evidence the split phase reconciles on
"""
import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent.parent / "tools" / "github"))
from _common import api_get, api_get_paged, get_token  # noqa: E402

MARKERS = ("research::", "design::", "spike::", "doc::")


def parse_ref(ref: str) -> tuple[str, str, int]:
    """'owner/repo#1' or the issue URL -> (owner, repo, number)."""
    m = re.match(r"https?://[^/]+/([^/]+)/([^/]+)/issues/(\d+)", ref.strip())
    if m:
        return m.group(1), m.group(2), int(m.group(3))
    m = re.fullmatch(r"([^/#]+)/([^/#]+)#(\d+)", ref.strip())
    if not m:
        sys.exit(f"Error: '{ref}' is not a GitHub epic ref. Expected owner/repo#<n>, "
                 "e.g. khai-nguyen-quang/dash-cam#1.")
    return m.group(1), m.group(2), int(m.group(3))


def classify(issue: dict) -> str:
    """Ticket kind from a `<kind>::` marker in the TITLE or the body.

    Same rule as the GitLab tool: humans write the marker in either field, and a
    non-implementation ticket seeded into the coding lane makes a coder try to
    implement a design task.
    """
    for field in ("title", "body"):
        text = (issue.get(field) or "").lstrip().lower()
        for m in MARKERS:
            if text.startswith(m):
                return m.rstrip(":")
    return "impl"


def child_ref(issue: dict) -> str:
    """A sub-issue -> 'owner/repo#<number>', honouring cross-repo children."""
    url = issue.get("repository_url") or ""
    m = re.search(r"/repos/([^/]+)/([^/]+)$", url)
    if m:
        return f"{m.group(1)}/{m.group(2)}#{issue['number']}"
    m = re.match(r"https?://[^/]+/([^/]+)/([^/]+)/issues/", issue.get("html_url") or "")
    if m:
        return f"{m.group(1)}/{m.group(2)}#{issue['number']}"
    return str(issue["number"])


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ref", help="owner/repo#<n>")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--refs-only", action="store_true")
    ap.add_argument("--detail", action="store_true",
                    help="per-child evidence for the split phase's reconcile step")
    a = ap.parse_args()

    owner, repo, number = parse_ref(a.ref)
    token = get_token()

    epic = api_get(f"/repos/{owner}/{repo}/issues/{number}", token)
    if epic.get("pull_request"):
        sys.exit(f"Error: {owner}/{repo}#{number} is a pull request, not an issue.")

    issues = api_get_paged(f"/repos/{owner}/{repo}/issues/{number}/sub_issues", token)

    if a.refs_only:
        for i in issues:
            print(child_ref(i))
        return
    if a.json:
        print(json.dumps({"epic": epic, "issues": issues}, indent=2))
        return
    if a.detail:
        print(f"{owner}/{repo}#{epic['number']}: {epic['title']}   ({len(issues)} children)\n")
        print(f"  {'ref':<34} {'state':<7} {'kind':<9} {'notes':>5}  "
              f"{'assignee':<14} {'updated':<11} title")
        print("  " + "-" * 116)
        for i in sorted(issues, key=lambda x: x["number"]):
            who = (i.get("assignee") or {}).get("login") or "-"
            print(f"  {child_ref(i):<34} {i['state']:<7} {classify(i):<9} "
                  f"{i.get('comments', 0):>5}  {who:<14} {i['updated_at'][:10]:<11} {i['title'][:40]}")
        print("\n  notes/assignee are the evidence for which duplicate survives:")
        print("  prefer the ticket carrying history over a freshly written one.")
        return

    print(f"{owner}/{repo}#{epic['number']}: {epic['title']}")
    print(f"State: {epic['state']}   Web: {epic.get('html_url', '')}")
    projects = sorted({child_ref(i).split('#')[0].split('/')[-1] for i in issues})
    print(f"Projects in scope: {', '.join(projects) if projects else '(none — no children yet)'}")
    print(f"\n--- Description ---\n{epic.get('body') or '(empty)'}")
    print(f"\n--- Children ({len(issues)}) ---")
    for i in issues:
        print(f"  {child_ref(i):<34} [{i['state']:<6}] {i['title']}")


if __name__ == "__main__":
    main()
