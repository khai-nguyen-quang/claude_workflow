#!/usr/bin/env python3
"""
Retrieve the GitHub issue associated with a pull request.

The PR title and body are scanned for "Ref #N", "Closes #N", "Fixes #N" and
"Resolves #N".  The issue is then fetched from the same repository.

Usage:
    fetch_issue_from_mr.py <pr-ref> [--json]

Arguments:
    pr-ref  Full URL or short ref for the PR.
            Short format: khai-nguyen-quang/dash-cam#PR!45
            Full URL:     https://github.com/khai-nguyen-quang/dash-cam/pull/45

Options:
    --json  Emit raw JSON from the GitHub API instead of formatted text.
    --help  Show this help.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import api_get, get_token, resolve_ref  # noqa: E402

LINK_PATTERN = re.compile(r"\b(?:ref|refs|close[sd]?|fix(?:e[sd])?|resolve[sd]?)\b[\s:]*#(\d+)", re.I)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Find the issue linked to a GitHub pull request.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("ref", help="PR ref (short or full URL)")
    parser.add_argument("--json", action="store_true", dest="as_json", help="Output raw JSON")
    args = parser.parse_args()

    token = get_token()
    kind, owner, repo, number = resolve_ref(args.ref)

    if kind != "mr":
        print(f"Error: ref '{args.ref}' is an issue, not a pull request.", file=sys.stderr)
        sys.exit(1)

    pr = api_get(f"/repos/{owner}/{repo}/pulls/{number}", token)
    haystack = f"{pr.get('title', '')}\n{pr.get('body') or ''}"

    matches = LINK_PATTERN.findall(haystack)
    if not matches:
        print(f"Error: no linked issue found in PR #{number} of {owner}/{repo}.", file=sys.stderr)
        print("  Looked for 'Ref #N', 'Closes #N', 'Fixes #N', 'Resolves #N'", file=sys.stderr)
        print("  in the title and body.", file=sys.stderr)
        sys.exit(1)

    # A PR body may name several issues; the first is the ticket it implements.
    issue_number = int(matches[0])
    issue = api_get(f"/repos/{owner}/{repo}/issues/{issue_number}", token)

    if args.as_json:
        print(json.dumps(issue, indent=2))
        return

    others = [m for m in matches[1:] if int(m) != issue_number]
    print(f"PR #{number}: {pr.get('title', '')}")
    print(f"Linked issue: {owner}/{repo}#{issue_number}")
    if others:
        print(f"Also referenced: {', '.join('#' + o for o in others)}")
    print("─" * 60)
    print(f"Title:  {issue.get('title', '')}")
    print(f"State:  {issue.get('state', '')}")
    print(f"Author: {(issue.get('user') or {}).get('login', 'unknown')}")
    print(f"URL:    {issue.get('html_url', '')}")
    print()
    print("Description:")
    print("─" * 60)
    print(issue.get("body") or "(no description)")


if __name__ == "__main__":
    main()
