#!/usr/bin/env python3
"""
Retrieve the GitLab Issue associated with a merge request.

The MR title (and description) is scanned for a "Ref #NNN" pattern.  The
issue is then fetched from the same project namespace as the MR.

Usage:
    fetch_issue_from_mr.py <mr-ref> [--json]

Arguments:
    mr-ref  Full URL or short ref for the MR.
            Short format: projectX#MR!178
            Full URL:     https://gitlab.company.com/.../merge_requests/178

Options:
    --json  Emit raw JSON from the GitLab API instead of formatted text.
    --help  Show this help.

Examples:
    ./fetch_issue_from_mr.py projectX#MR!178
    ./fetch_issue_from_mr.py projectX#MR!178 --json
    ./fetch_issue_from_mr.py https://gitlab.company.com/.../merge_requests/178
"""

from __future__ import annotations

import argparse
import json
import re
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from _common import api_get, encode_project, get_token, resolve_ref


def _find_issue_iid(text: str) -> int | None:
    """Return the first issue IID found via 'Ref #NNN' in text, or None."""
    m = re.search(r"[Rr]ef\s+#(\d+)", text)
    if m:
        return int(m.group(1))
    return None


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch the GitLab Issue linked in an MR via 'Ref #NNN'.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("ref", help="MR ref (short or full URL)")
    parser.add_argument("--json", action="store_true", dest="as_json", help="Output raw JSON")
    args = parser.parse_args()

    token = get_token()
    kind, project_path, iid = resolve_ref(args.ref)

    if kind != "mr":
        print(f"Error: ref '{args.ref}' is an issue, not a merge request.", file=sys.stderr)
        print("  Use fetch_ticket_description.py for issues.", file=sys.stderr)
        sys.exit(1)

    encoded = encode_project(project_path)
    mr_data = api_get(f"/projects/{encoded}/merge_requests/{iid}", token)

    mr_title = mr_data.get("title", "")
    mr_desc = mr_data.get("description") or ""

    # Search title first, then description
    issue_iid = _find_issue_iid(mr_title) or _find_issue_iid(mr_desc)

    if issue_iid is None:
        print(f"Error: no 'Ref #NNN' pattern found in MR !{iid}.", file=sys.stderr)
        print(f"  Title:       {mr_title}", file=sys.stderr)
        print(f"  Description: {mr_desc[:200]}{'…' if len(mr_desc) > 200 else ''}", file=sys.stderr)
        sys.exit(1)

    print(f"MR !{iid} references issue #{issue_iid} — fetching…")
    print()

    issue_data = api_get(f"/projects/{encoded}/issues/{issue_iid}", token)

    if args.as_json:
        print(json.dumps(issue_data, indent=2))
        return

    state = issue_data.get("state", "unknown")
    title = issue_data.get("title", "(no title)")
    description = issue_data.get("description") or "(no description)"
    author = issue_data.get("author", {}).get("name", "unknown")
    created = (issue_data.get("created_at") or "")[:10]
    updated = (issue_data.get("updated_at") or "")[:10]
    web_url = issue_data.get("web_url", "")
    labels = ", ".join(issue_data.get("labels") or []) or "(none)"
    assignees = (
        ", ".join(a.get("name", "") for a in (issue_data.get("assignees") or [])) or "(none)"
    )
    milestone = (issue_data.get("milestone") or {}).get("title", "(none)")

    print(f"Issue #{issue_iid} — {title}")
    print("─" * 60)
    print(f"Project:    {project_path}")
    print(f"State:      {state}")
    print(f"Author:     {author}  ({created})")
    print(f"Updated:    {updated}")
    print(f"Assignees:  {assignees}")
    print(f"Labels:     {labels}")
    print(f"Milestone:  {milestone}")
    print(f"URL:        {web_url}")
    print()
    print("Description:")
    print("─" * 60)
    print(description)


if __name__ == "__main__":
    main()
