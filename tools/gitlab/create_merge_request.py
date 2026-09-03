#!/usr/bin/env python3
"""
Create a new merge request on GitLab.

Usage:
    create_merge_request.py <project> [options]

Arguments:
    project   Short project name (projectX) or full path (group/sub/projectX).
              A short name (no slash) is expanded with GL_NAMESPACE.

Options:
    --source <branch>        Source branch. Default: current branch of the local repo.
    --target <branch>        Target branch. Default: the project's default branch.
    --title <title>          MR title. Default: latest commit subject (or issue title).
    --description <text>      MR description body.
    --description-file <path> Read description body from a file.
                              If neither is given, the built-in template is used.
    --issue <iid>            Link an issue: appends "Closes #<iid>" to the description
                              and, if no --title given, uses the issue title.
    --draft                  Mark as draft (prefixes the title with "Draft: ").
    --label <label>          Label to apply (repeatable, or comma-separated).
    --remove-source-branch   Delete the source branch when the MR is merged.
    --squash                 Squash commits when merging.
    --dry-run                Print the request payload without creating the MR.
    --help, -h               Show this help.

Examples:
    ./create_merge_request.py projectX
    ./create_merge_request.py projectX --target develop --issue 310
    ./create_merge_request.py projectX --title "[Refactor] Extract DrainQueue" --draft
    ./create_merge_request.py projectX --description-file mr_body.md --remove-source-branch
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import (
    GITLAB_NAMESPACE,
    GITLAB_URL,
    api_get,
    api_post,
    encode_project,
    get_token,
)

# WORKSPACE_ROOT is three levels above tools/gitlab/ (the parent of claude_workflow/).
WORKSPACE_ROOT = Path(__file__).resolve().parents[3]

# Default description, per claude_workflow/instructions/gitlab.md "Merge request creation".
TEMPLATE = """\
# Summary

---

# Implementation Details

## Important note

## Core changes:


## Simulation support:


## Document

## Known bug:

---

# How It Was Tested
- Manual validation with recorded video sequences
- Automated validation
    - CI pipeline passed successfully
"""


def resolve_project(arg: str) -> str:
    """Expand a short project name with GL_NAMESPACE; leave full paths untouched."""
    return arg if "/" in arg else f"{GITLAB_NAMESPACE}/{arg}"


def git_output(repo: Path, *args: str) -> str:
    """Run a git command in `repo` and return stripped stdout, or '' on failure."""
    try:
        return subprocess.check_output(
            ["git", "-C", str(repo), *args],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def remote_branch_exists(encoded_project: str, branch: str, token: str) -> bool:
    """Return True if `branch` exists on the remote project (404 → False)."""
    endpoint = f"/projects/{encoded_project}/repository/branches/{urllib.parse.quote(branch, safe='')}"
    req = urllib.request.Request(
        f"{GITLAB_URL}/api/v4{endpoint}",
        headers={"PRIVATE-TOKEN": token},
    )
    try:
        urllib.request.urlopen(req)
        return True
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return False
        body = exc.read().decode(errors="replace")
        print(f"Error: GitLab API {exc.code} checking branch '{branch}'", file=sys.stderr)
        print(f"  {body}", file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as exc:
        print(f"Error: cannot reach GitLab: {exc.reason}", file=sys.stderr)
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a GitLab merge request.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("project", help="Short project name or full path")
    parser.add_argument("--source", help="Source branch (default: current local branch)")
    parser.add_argument("--target", help="Target branch (default: project default branch)")
    parser.add_argument("--title", help="MR title (default: latest commit subject)")
    parser.add_argument("--description", help="MR description body")
    parser.add_argument("--description-file", metavar="PATH", help="Read description from file")
    parser.add_argument("--issue", type=int, metavar="IID", help="Issue to close and derive title from")
    parser.add_argument("--draft", action="store_true", help="Mark MR as draft")
    parser.add_argument("--label", action="append", default=[], metavar="LABEL",
                        help="Label to apply (repeatable; or comma-separated)")
    parser.add_argument("--remove-source-branch", action="store_true", help="Delete source branch on merge")
    parser.add_argument("--squash", action="store_true", help="Squash commits on merge")
    parser.add_argument("--dry-run", action="store_true", help="Print payload without creating the MR")
    args = parser.parse_args()

    token = get_token()
    project_path = resolve_project(args.project)
    encoded = encode_project(project_path)
    project_name = project_path.rsplit("/", 1)[-1]
    repo = WORKSPACE_ROOT / project_name

    # Source branch: explicit, else the current branch of the local repo.
    source = args.source
    if not source:
        if not (repo / ".git").exists():
            print(f"Error: local repo not found at '{repo}'.", file=sys.stderr)
            print("  Pass --source explicitly, or clone the project there.", file=sys.stderr)
            sys.exit(1)
        source = git_output(repo, "rev-parse", "--abbrev-ref", "HEAD")
        if not source or source == "HEAD":
            print("Error: could not determine current branch. Pass --source explicitly.", file=sys.stderr)
            sys.exit(1)

    # Target branch: explicit, else the project's default branch.
    target = args.target
    if not target:
        project_info = api_get(f"/projects/{encoded}", token)
        target = project_info.get("default_branch", "")
        if not target:
            print("Error: could not determine default branch. Pass --target explicitly.", file=sys.stderr)
            sys.exit(1)

    if source == target:
        print(f"Error: source and target branch are both '{source}'.", file=sys.stderr)
        sys.exit(1)

    # Pre-flight: GitLab rejects an MR whose source branch is not on the remote.
    if not remote_branch_exists(encoded, source, token):
        print(f"Error: source branch '{source}' not found on the remote.", file=sys.stderr)
        print("  Push it first, e.g. branch/push_branch.sh --branch " + source, file=sys.stderr)
        sys.exit(1)

    # Description: --description, --description-file, or the built-in template.
    if args.description is not None:
        description = args.description
    elif args.description_file:
        description = Path(args.description_file).read_text()
    else:
        description = TEMPLATE

    if args.issue:
        description = description.rstrip() + f"\n\nCloses #{args.issue}\n"

    # Title: explicit, else issue title, else latest commit subject.
    title = args.title
    if not title and args.issue:
        issue = api_get(f"/projects/{encoded}/issues/{args.issue}", token)
        title = issue.get("title", "")
    if not title:
        title = git_output(repo, "log", "-1", "--pretty=%s")
    if not title:
        print("Error: could not determine a title. Pass --title explicitly.", file=sys.stderr)
        sys.exit(1)

    if args.draft and not title.lower().startswith("draft:"):
        title = f"Draft: {title}"

    # Labels: flatten repeated --label flags and split any comma-separated values.
    labels = [lbl.strip() for group in args.label for lbl in group.split(",") if lbl.strip()]

    payload: dict = {
        "source_branch": source,
        "target_branch": target,
        "title": title,
        "description": description,
        "remove_source_branch": args.remove_source_branch,
        "squash": args.squash,
    }
    if labels:
        payload["labels"] = ",".join(labels)

    print(f"Project: {project_path}")
    print(f"Branch:  {source}  →  {target}")
    print(f"Title:   {title}")
    if labels:
        print(f"Labels:  {', '.join(labels)}")

    if args.dry_run:
        import json
        print("\n[dry-run] POST /projects/.../merge_requests")
        print(json.dumps(payload, indent=2))
        return

    result = api_post(f"/projects/{encoded}/merge_requests", token, payload)
    iid = result.get("iid", "?")
    web_url = result.get("web_url", "")
    print(f"\nMerge request !{iid} created.")
    if web_url:
        print(f"URL: {web_url}")


if __name__ == "__main__":
    main()
