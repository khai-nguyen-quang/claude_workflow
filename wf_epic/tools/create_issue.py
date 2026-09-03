#!/usr/bin/env python3
"""
Create a GitLab issue and link it to a group-level epic.

OUTWARD-FACING AND IRREVERSIBLE. The split phase must show the human every ticket and
get explicit confirmation before this runs without --dry-run.

The linking trap: assigning an issue to an epic needs the issue's GLOBAL id, not its
iid (openpilot#508 is iid 508 but global id 204759). We create first, then link with
the id from the create response, then read epic_iid back to prove the link landed.

Usage:
    create_issue.py openpilot --title "..." --description-file body.md \
                    --epic 116 --label backend --dry-run
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent / "tools" / "gitlab"))
from _common import (GITLAB_NAMESPACE, api_get, api_post,  # noqa: E402
                     encode_project, get_token)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("project", help="short project name (e.g. openpilot) or full path")
    ap.add_argument("--title", required=True)
    ap.add_argument("--description")
    ap.add_argument("--description-file", metavar="PATH")
    ap.add_argument("--epic", type=int, metavar="IID", help="parent epic iid to link to")
    ap.add_argument("--label", action="append", default=[], metavar="LABEL")
    ap.add_argument("--dry-run", action="store_true", help="print the payload, create nothing")
    a = ap.parse_args()

    if a.description_file:
        a.description = Path(a.description_file).read_text()
    project = a.project if "/" in a.project else f"{GITLAB_NAMESPACE}/{a.project}"
    payload = {"title": a.title, "description": a.description or "",
               "labels": ",".join(a.label)}

    if a.dry_run:
        print(f"DRY RUN — would create in {project}:")
        print(f"  title  : {a.title}")
        print(f"  labels : {', '.join(a.label) or '(none)'}")
        print(f"  epic   : {a.epic if a.epic else '(none)'}")
        body = (a.description or "").strip().splitlines()
        print("  body   : " + (body[0][:70] if body else "(empty)")
              + (f" … (+{len(body) - 1} lines)" if len(body) > 1 else ""))
        return

    token = get_token()
    issue = api_post(f"/projects/{encode_project(project)}/issues", token, payload)
    ref = f"{a.project.split('/')[-1]}#{issue['iid']}"
    print(f"created {ref}  (global id {issue['id']})  {issue['web_url']}")

    if not a.epic:
        return

    grp = encode_project(GITLAB_NAMESPACE)
    api_post(f"/groups/{grp}/epics/{a.epic}/issues/{issue['id']}", token, {})
    check = api_get(f"/projects/{encode_project(project)}/issues/{issue['iid']}", token)
    if check.get("epic_iid") == a.epic:
        print(f"linked  {ref} -> Epic#{a.epic}  (verified via epic_iid)")
    else:
        print(f"WARNING: {ref} created but epic_iid reads back as "
              f"{check.get('epic_iid')!r}, expected {a.epic}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
