#!/usr/bin/env python3
"""
Update a group-level GitLab epic's description.

Epics are GROUP-level (instructions/gitlab.md):
    Epic#91  ->  ${GL_URL}/groups/${GL_NAMESPACE}/-/epics/91
so this uses /groups/<namespace>/epics/<iid>, never a project endpoint.

The new description is read from a file, never from an argument: a description is
multi-line Markdown and shell quoting mangles it silently.

Usage:
    update_epic.py Epic#91 --description-file <path>
    update_epic.py Epic#91 --description-file <path> --dry-run
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "tools" / "gitlab"))
from _common import GITLAB_NAMESPACE, api_put, get_token  # noqa: E402

from fetch_epic import parse_ref  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("ref", help="Epic#<id>")
    ap.add_argument("--description-file", required=True, type=Path)
    ap.add_argument("--dry-run", action="store_true",
                    help="Print what would be sent and exit without writing.")
    a = ap.parse_args()

    iid = parse_ref(a.ref)
    if not a.description_file.exists():
        sys.exit(f"Error: {a.description_file} not found")
    description = a.description_file.read_text()

    namespace = GITLAB_NAMESPACE.replace("/", "%2F")
    endpoint = f"/groups/{namespace}/epics/{iid}"

    if a.dry_run:
        print(f"PUT {endpoint}\n{len(description)} chars, {description.count(chr(10)) + 1} lines")
        return

    epic = api_put(endpoint, get_token(), {"description": description})
    print(f"Updated Epic#{epic['iid']}: {epic['title']}")
    print(f"  {epic.get('web_url', '')}")


if __name__ == "__main__":
    main()
