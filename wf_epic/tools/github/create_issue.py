#!/usr/bin/env python3
"""
Create a GitHub issue and attach it to a parent issue as a sub-issue.

OUTWARD-FACING AND IRREVERSIBLE. The split phase must show the human every ticket
and get explicit confirmation before this runs without --dry-run.

The linking trap, identical in shape to the GitLab epic version: attaching a
sub-issue takes the child's GLOBAL id, not its number (#7 in a repo might be id
3312847612). We create first, then link with the id from the create response,
then read the children back to prove the link landed.

Usage:
    create_issue.py owner/repo --title "..." --description-file body.md \
                    --parent 1 --label backend --dry-run
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent.parent / "tools" / "github"))
from _common import api_get_paged, api_post, get_token  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("repo", help="owner/repo (e.g. khai-nguyen-quang/dash-cam)")
    ap.add_argument("--title", required=True)
    ap.add_argument("--description")
    ap.add_argument("--description-file", metavar="PATH")
    # --epic is accepted as an alias so callers written against the GitLab tool
    # keep working unchanged.
    ap.add_argument("--parent", "--epic", type=int, metavar="NUMBER", dest="parent",
                    help="parent issue number to attach this issue to as a sub-issue")
    ap.add_argument("--label", action="append", default=[], metavar="LABEL")
    ap.add_argument("--dry-run", action="store_true", help="print the payload, create nothing")
    a = ap.parse_args()

    if "/" not in a.repo:
        sys.exit(f"Error: '{a.repo}' must be owner/repo — a GitHub ref always carries the owner.")
    owner, repo = a.repo.split("/", 1)

    if a.description_file:
        a.description = Path(a.description_file).read_text()

    payload = {"title": a.title, "body": a.description or "", "labels": a.label}

    if a.dry_run:
        print(f"DRY RUN — would create in {a.repo}:")
        print(f"  title  : {a.title}")
        print(f"  labels : {', '.join(a.label) or '(none)'}")
        print(f"  parent : {f'{a.repo}#{a.parent}' if a.parent else '(none)'}")
        body = (a.description or "").strip().splitlines()
        print("  body   : " + (body[0][:70] if body else "(empty)")
              + (f" … (+{len(body) - 1} lines)" if len(body) > 1 else ""))
        return

    token = get_token()
    issue = api_post(f"/repos/{owner}/{repo}/issues", token, payload)
    ref = f"{a.repo}#{issue['number']}"
    print(f"created {ref}  (global id {issue['id']})  {issue['html_url']}")

    if not a.parent:
        return

    api_post(f"/repos/{owner}/{repo}/issues/{a.parent}/sub_issues", token,
             {"sub_issue_id": issue["id"]})

    children = api_get_paged(f"/repos/{owner}/{repo}/issues/{a.parent}/sub_issues", token)
    if any(c.get("number") == issue["number"] for c in children):
        print(f"linked  {ref} -> {a.repo}#{a.parent}  (verified by reading the children back)")
    else:
        print(f"WARNING: {ref} created but it does not appear among the sub-issues of "
              f"{a.repo}#{a.parent}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
