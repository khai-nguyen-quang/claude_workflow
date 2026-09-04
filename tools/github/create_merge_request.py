#!/usr/bin/env python3
"""
Create a new pull request on GitHub.

Named create_merge_request.py to match its GitLab counterpart: the workflow's
operation vocabulary is shared across forges, and MR == PR.

Usage:
    create_merge_request.py <owner/repo> [options]

Arguments:
    owner/repo  Repository to open the pull request in. A GitHub ref always
                carries the owner, so a bare name is rejected.

Options:
    --source <branch>        Source (head) branch. Default: current branch of the local repo.
    --target <branch>        Target (base) branch. Default: the repository's default branch.
    --title <title>          PR title. Default: linked issue title, else latest commit subject.
    --description <text>     PR body.
    --description-file <path> Read the body from a file.
                             If neither is given, the built-in template is used.
    --issue <number>         Link an issue: appends "Closes #<n>" to the body
                             and, if no --title given, uses the issue title.
    --draft                  Open as a draft pull request.
    --label <label>          Label to apply (repeatable, or comma-separated).
    --remove-source-branch   Accepted for CLI parity; GitHub decides this at merge time.
    --squash                 Accepted for CLI parity; GitHub decides this at merge time.
    --dry-run                Print the request payload without creating the PR.
    --help, -h               Show this help.

Examples:
    ./create_merge_request.py khai-nguyen-quang/dash-cam
    ./create_merge_request.py khai-nguyen-quang/dash-cam --target master --issue 3
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import api_exists, api_get, api_post, get_token  # noqa: E402

# WORKSPACE_ROOT is three levels above tools/github/ (the parent of claude_workflow/).
WORKSPACE_ROOT = Path(__file__).resolve().parents[3]

# Default description, per claude_workflow/instructions/github.md.
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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a GitHub pull request.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("repo", help="owner/repo")
    parser.add_argument("--source", help="Head branch (default: current local branch)")
    parser.add_argument("--target", help="Base branch (default: repository default branch)")
    parser.add_argument("--title", help="PR title (default: latest commit subject)")
    parser.add_argument("--description", help="PR body")
    parser.add_argument("--description-file", metavar="PATH", help="Read body from file")
    parser.add_argument("--issue", type=int, metavar="NUMBER",
                        help="Issue to close and derive the title from")
    parser.add_argument("--draft", action="store_true", help="Open as a draft")
    parser.add_argument("--label", action="append", default=[], metavar="LABEL",
                        help="Label to apply (repeatable; or comma-separated)")
    parser.add_argument("--remove-source-branch", action="store_true",
                        help="Accepted for parity; GitHub applies this at merge time")
    parser.add_argument("--squash", action="store_true",
                        help="Accepted for parity; GitHub applies this at merge time")
    parser.add_argument("--dry-run", action="store_true", help="Print payload without creating")
    args = parser.parse_args()

    if "/" not in args.repo:
        print(f"Error: '{args.repo}' must be owner/repo.", file=sys.stderr)
        print("  A GitHub ref always carries the owner; a bare name is a GitLab ref.", file=sys.stderr)
        sys.exit(1)
    owner, repo_name = args.repo.split("/", 1)

    token = get_token()
    local_repo = WORKSPACE_ROOT / repo_name

    # Source branch: explicit, else the current branch of the local repo.
    source = args.source
    if not source:
        if not (local_repo / ".git").exists():
            print(f"Error: local repo not found at '{local_repo}'.", file=sys.stderr)
            print("  Pass --source explicitly, or clone the repository there.", file=sys.stderr)
            sys.exit(1)
        source = git_output(local_repo, "rev-parse", "--abbrev-ref", "HEAD")
        if not source or source == "HEAD":
            print("Error: could not determine current branch. Pass --source explicitly.", file=sys.stderr)
            sys.exit(1)

    # Target branch: explicit, else the repository's default branch.
    target = args.target
    if not target:
        target = api_get(f"/repos/{owner}/{repo_name}", token).get("default_branch", "")
        if not target:
            print("Error: could not determine default branch. Pass --target explicitly.", file=sys.stderr)
            sys.exit(1)

    if source == target:
        print(f"Error: source and target branch are both '{source}'.", file=sys.stderr)
        sys.exit(1)

    # Pre-flight: GitHub rejects a PR whose head branch is not on the remote.
    if not api_exists(f"/repos/{owner}/{repo_name}/branches/{source}", token):
        print(f"Error: source branch '{source}' not found on the remote.", file=sys.stderr)
        print(f"  Push it first, e.g. branch/push_branch.sh --branch {source}", file=sys.stderr)
        sys.exit(1)

    if args.description is not None:
        description = args.description
    elif args.description_file:
        description = Path(args.description_file).read_text()
    else:
        description = TEMPLATE

    if args.issue:
        description = description.rstrip() + f"\n\nCloses #{args.issue}\n"

    title = args.title
    if not title and args.issue:
        title = api_get(f"/repos/{owner}/{repo_name}/issues/{args.issue}", token).get("title", "")
    if not title:
        title = git_output(local_repo, "log", "-1", "--pretty=%s")
    if not title:
        print("Error: could not determine a title. Pass --title explicitly.", file=sys.stderr)
        sys.exit(1)

    labels = [lbl.strip() for group in args.label for lbl in group.split(",") if lbl.strip()]

    payload = {
        "title": title,
        "head": source,
        "base": target,
        "body": description,
        "draft": args.draft,
    }

    if args.dry_run:
        print(f"DRY RUN — would create in {args.repo}:")
        print(f"  title  : {title}")
        print(f"  branch : {source}  →  {target}")
        print(f"  draft  : {args.draft}")
        print(f"  labels : {', '.join(labels) or '(none)'}")
        print(f"  issue  : {args.issue if args.issue else '(none)'}")
        body = description.strip().splitlines()
        print("  body   : " + (body[0][:70] if body else "(empty)")
              + (f" … (+{len(body) - 1} lines)" if len(body) > 1 else ""))
        return

    if args.remove_source_branch or args.squash:
        print("Note: --remove-source-branch and --squash are merge-time settings on GitHub;")
        print("      they are not part of pull request creation and were not applied.")

    pr = api_post(f"/repos/{owner}/{repo_name}/pulls", token, payload)
    print(f"created {args.repo}#PR!{pr['number']}  {pr['html_url']}")

    # Labels live on the issue side of a pull request, so they are a second call.
    if labels:
        api_post(f"/repos/{owner}/{repo_name}/issues/{pr['number']}/labels", token,
                 {"labels": labels})
        print(f"labelled {', '.join(labels)}")


if __name__ == "__main__":
    main()
