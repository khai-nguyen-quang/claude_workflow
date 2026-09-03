#!/usr/bin/env python3
"""
Fetch a group-level GitLab epic and its child issues.

Epics are GROUP-level (instructions/gitlab.md):
    Epic#60  ->  ${GL_URL}/groups/${GL_NAMESPACE}/-/epics/60
so this uses /groups/<namespace>/epics/<iid>, never a project endpoint.

Verified against gitlab.cartrack.com (GitLab 19.3.1-ee): the REST epics API is live
and emits no deprecation headers, though epics now carry a work_item_id alongside iid
as the work-items migration proceeds underneath.

Usage:
    fetch_epic.py Epic#60              # description + children
    fetch_epic.py Epic#60 --json
    fetch_epic.py Epic#60 --refs-only  # child refs, one per line, for the seed script
    fetch_epic.py Epic#60 --detail     # children + the evidence the split phase reconciles on
"""
import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "tools" / "gitlab"))
from _common import GITLAB_NAMESPACE, api_get, api_get_paged, encode_project, get_token  # noqa: E402


def parse_ref(ref: str) -> int:
    m = re.fullmatch(r"(?i)epic#(\d+)", ref.strip())
    if not m:
        sys.exit(f"Error: '{ref}' is not an epic ref. Expected Epic#<id>, e.g. Epic#60.")
    return int(m.group(1))


MARKERS = ("research::", "design::", "spike::", "doc::")


def classify(issue: dict) -> str:
    """Ticket kind from a `<kind>::` marker in the TITLE or the description.

    The workflow's own convention puts the marker at the start of the description
    (`research::`), but humans write it in the title just as often — Epic#91's
    design:: tickets do. Check both, or non-implementation tickets get seeded into
    the coding lane and a coder tries to implement a design task.
    """
    for field in ("title", "description"):
        text = (issue.get(field) or "").lstrip().lower()
        for m in MARKERS:
            if text.startswith(m):
                return m.rstrip(":")
    return "impl"


def child_ref(issue: dict) -> str:
    """'group/sub/openpilot#508' -> 'openpilot#508'"""
    full = issue.get("references", {}).get("full", "")
    return f"{full.split('#')[0].split('/')[-1]}#{issue['iid']}" if full else str(issue["iid"])


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ref", help="Epic#<id>")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--refs-only", action="store_true")
    ap.add_argument("--detail", action="store_true",
                    help="per-child evidence for the split phase's reconcile step")
    a = ap.parse_args()

    iid, token = parse_ref(a.ref), get_token()
    grp = encode_project(GITLAB_NAMESPACE)
    epic = api_get(f"/groups/{grp}/epics/{iid}", token)
    issues = api_get_paged(f"/groups/{grp}/epics/{iid}/issues", token)

    if a.refs_only:
        for i in issues:
            print(child_ref(i))
        return
    if a.json:
        print(json.dumps({"epic": epic, "issues": issues}, indent=2))
        return
    if a.detail:
        print(f"Epic#{epic['iid']}: {epic['title']}   ({len(issues)} children)\n")
        print(f"  {'ref':<16} {'state':<7} {'kind':<9} {'notes':>5} {'MRs':>4} {'wt':>3}  "
              f"{'assignee':<14} {'updated':<11} title")
        print("  " + "-" * 116)
        for i in sorted(issues, key=lambda x: x["iid"]):
            kind = classify(i)
            who = (i.get("assignee") or {}).get("username") or "-"
            print(f"  {child_ref(i):<16} {i['state']:<7} {kind:<9} "
                  f"{i.get('user_notes_count', 0):>5} {i.get('merge_requests_count', 0):>4} "
                  f"{i.get('weight') or '-':>3}  {who:<14} {i['updated_at'][:10]:<11} {i['title'][:44]}")
        print("\n  notes/MRs/assignee are the evidence for which duplicate survives:")
        print("  prefer the ticket carrying history over a freshly written one.")
        return

    print(f"Epic#{epic['iid']}: {epic['title']}")
    print(f"State: {epic['state']}   Web: {epic.get('web_url', '')}")
    projects = sorted({child_ref(i).split('#')[0] for i in issues})
    print(f"Projects in scope: {', '.join(projects) if projects else '(none — no children yet)'}")
    print(f"\n--- Description ---\n{epic.get('description') or '(empty)'}")
    print(f"\n--- Children ({len(issues)}) ---")
    for i in issues:
        print(f"  {child_ref(i):<20} [{i['state']:<6}] {i['title']}")


if __name__ == "__main__":
    main()
