#!/usr/bin/env python3
"""
Fetch the description of a GitHub issue.

Serves both roles in the workflow: a parent issue (the epic) and a sub-issue
(the ticket) are the same object to GitHub, so one tool reads either.

Usage:
    fetch_ticket_description.py <ref> [--json]

Arguments:
    ref     Full URL or short ref.
            Short format: khai-nguyen-quang/dash-cam#12
            Full URL:     https://github.com/khai-nguyen-quang/dash-cam/issues/12

Options:
    --json  Emit raw JSON from the GitHub API instead of formatted text.
    --help  Show this help.

Examples:
    ./fetch_ticket_description.py khai-nguyen-quang/dash-cam#12
    ./fetch_ticket_description.py khai-nguyen-quang/dash-cam#12 --json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import api_get, get_token, resolve_ref  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch a GitHub issue description.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("ref", help="Issue ref (short or full URL)")
    parser.add_argument("--json", action="store_true", dest="as_json", help="Output raw JSON")
    args = parser.parse_args()

    token = get_token()
    kind, owner, repo, number = resolve_ref(args.ref)

    if kind != "issue":
        print(f"Error: ref '{args.ref}' resolves to a pull request, not an issue.", file=sys.stderr)
        print("  Use fetch_mr_content.sh for pull requests.", file=sys.stderr)
        sys.exit(1)

    data = api_get(f"/repos/{owner}/{repo}/issues/{number}", token)

    if data.get("pull_request"):
        print(f"Error: #{number} in {owner}/{repo} is a pull request, not an issue.", file=sys.stderr)
        print(f"  Use fetch_mr_content.sh {owner}/{repo}#PR!{number}", file=sys.stderr)
        sys.exit(1)

    if args.as_json:
        print(json.dumps(data, indent=2))
        return

    state = data.get("state", "unknown")
    title = data.get("title", "(no title)")
    description = data.get("body") or "(no description)"
    author = (data.get("user") or {}).get("login", "unknown")
    created = (data.get("created_at") or "")[:10]
    updated = (data.get("updated_at") or "")[:10]
    web_url = data.get("html_url", "")
    labels = ", ".join(lbl.get("name", "") for lbl in (data.get("labels") or [])) or "(none)"
    assignees = ", ".join(a.get("login", "") for a in (data.get("assignees") or [])) or "(none)"
    milestone = (data.get("milestone") or {}).get("title", "(none)")

    print(f"Issue #{number} — {title}")
    print("─" * 60)
    print(f"Repository: {owner}/{repo}")
    print(f"State:      {state}")
    print(f"Author:     {author}  ({created})")
    print(f"Updated:    {updated}")
    print(f"Assignees:  {assignees}")
    print(f"Labels:     {labels}")
    print(f"Milestone:  {milestone}")

    # Sub-issue relationships are what make an issue usable as an epic, so surface
    # them here rather than making the caller run fetch_epic.py to find out.
    summary = data.get("sub_issues_summary") or {}
    if summary.get("total"):
        print(f"Sub-issues: {summary.get('completed', 0)}/{summary['total']} completed")
    parent = data.get("parent") or {}
    if parent:
        print(f"Parent:     {owner}/{repo}#{parent.get('number')} — {parent.get('title', '')}")

    print(f"URL:        {web_url}")
    print()
    print("Description:")
    print("─" * 60)
    print(description)


if __name__ == "__main__":
    main()
