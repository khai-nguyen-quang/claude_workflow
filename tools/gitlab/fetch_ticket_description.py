#!/usr/bin/env python3
"""
Fetch the description of a GitLab issue (or work item).

Usage:
    fetch_ticket_description.py <ref> [--json]

Arguments:
    ref     Full URL or short ref.
            Short format: projectX#300  (issue 300 in the projectX project)
            Full URL:     https://gitlab.company.com/.../work_items/300

Options:
    --json  Emit raw JSON from the GitLab API instead of formatted text.
    --help  Show this help.

Examples:
    ./fetch_ticket_description.py projectX#300
    ./fetch_ticket_description.py projectX#306 --json
    ./fetch_ticket_description.py https://gitlab.company.com/.../issues/300
"""

from __future__ import annotations

import argparse
import json
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from _common import api_get, encode_project, get_token, resolve_ref


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch a GitLab issue description.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("ref", help="Issue ref (short or full URL)")
    parser.add_argument("--json", action="store_true", dest="as_json", help="Output raw JSON")
    args = parser.parse_args()

    token = get_token()
    kind, project_path, iid = resolve_ref(args.ref)

    if kind != "issue":
        print(f"Error: ref '{args.ref}' resolves to a merge request, not an issue.", file=sys.stderr)
        print("  Use fetch_mr_content.sh for merge requests.", file=sys.stderr)
        sys.exit(1)

    encoded = encode_project(project_path)
    data = api_get(f"/projects/{encoded}/issues/{iid}", token)

    if args.as_json:
        print(json.dumps(data, indent=2))
        return

    state = data.get("state", "unknown")
    title = data.get("title", "(no title)")
    description = data.get("description") or "(no description)"
    author = data.get("author", {}).get("name", "unknown")
    created = (data.get("created_at") or "")[:10]
    updated = (data.get("updated_at") or "")[:10]
    web_url = data.get("web_url", "")
    labels = ", ".join(data.get("labels") or []) or "(none)"
    assignees = ", ".join(a.get("name", "") for a in (data.get("assignees") or [])) or "(none)"
    milestone = (data.get("milestone") or {}).get("title", "(none)")

    print(f"Issue #{iid} — {title}")
    print(f"{'─' * 60}")
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
