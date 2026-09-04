#!/usr/bin/env python3
"""
Post a review comment on a GitHub pull request.

Usage:
    upload_review_comment.py <ref> <body>
    upload_review_comment.py <ref> --file <comment.txt>
    upload_review_comment.py <ref> - < comment.txt          (read body from stdin)

    # Inline comment on a specific file/line:
    upload_review_comment.py <ref> <body> --inline-file <path> --new-line <N> [--sha <commit_sha>]

Arguments:
    ref     Full URL or short ref for the PR.
            Short format: khai-nguyen-quang/dash-cam#PR!45
            Full URL:     https://github.com/khai-nguyen-quang/dash-cam/pull/45

Options:
    --file <path>         Read comment body from a file instead of argv.
    --inline-file <path>  File path (in the repo) for an inline comment.
    --new-line <N>        Line number on the new side for an inline comment.
    --old-line <N>        Line number on the old side (for a removed/context line).
    --sha <sha>           Commit SHA for inline comments (defaults to the PR head SHA).
    --help, -h            Show this help.

Examples:
    ./upload_review_comment.py khai-nguyen-quang/dash-cam#PR!45 "LGTM, nice refactor."
    ./upload_review_comment.py khai-nguyen-quang/dash-cam#PR!45 --file review.txt
    ./upload_review_comment.py khai-nguyen-quang/dash-cam#PR!45 "Fix null check here" \\
        --inline-file src/camera.cc --new-line 42
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import api_get, api_post, get_token, resolve_ref  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Post a review comment on a GitHub pull request.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("ref", help="PR ref (short or full URL)")
    parser.add_argument("body", nargs="?", help="Comment body, or '-' to read stdin")
    parser.add_argument("--file", metavar="PATH", help="Read comment body from a file")
    parser.add_argument("--inline-file", metavar="PATH", help="Repo file path for an inline comment")
    parser.add_argument("--new-line", type=int, metavar="N", help="Line on the new side")
    parser.add_argument("--old-line", type=int, metavar="N", help="Line on the old side")
    parser.add_argument("--sha", help="Commit SHA for inline comments")
    args = parser.parse_args()

    if args.file:
        body = Path(args.file).read_text()
    elif args.body == "-":
        body = sys.stdin.read()
    elif args.body:
        body = args.body
    else:
        print("Error: a comment body is required (argv, --file, or '-' for stdin).", file=sys.stderr)
        sys.exit(1)

    if not body.strip():
        print("Error: comment body is empty.", file=sys.stderr)
        sys.exit(1)

    token = get_token()
    kind, owner, repo, number = resolve_ref(args.ref)

    if kind != "mr":
        print(f"Error: ref '{args.ref}' is an issue, not a pull request.", file=sys.stderr)
        sys.exit(1)

    if not args.inline_file:
        note = api_post(f"/repos/{owner}/{repo}/issues/{number}/comments", token, {"body": body})
        print(f"Posted comment {note['id']} on {owner}/{repo}#PR!{number}")
        print(f"  {note['html_url']}")
        return

    if args.new_line is None and args.old_line is None:
        print("Error: --inline-file needs --new-line or --old-line.", file=sys.stderr)
        sys.exit(1)

    sha = args.sha
    if not sha:
        sha = (api_get(f"/repos/{owner}/{repo}/pulls/{number}", token).get("head") or {}).get("sha", "")
        if not sha:
            print("Error: could not determine the PR head SHA. Pass --sha.", file=sys.stderr)
            sys.exit(1)

    # GitHub addresses an inline comment by side + line, where RIGHT is the new
    # side of the diff and LEFT the old one.
    payload = {
        "body": body,
        "commit_id": sha,
        "path": args.inline_file,
        "side": "RIGHT" if args.new_line is not None else "LEFT",
        "line": args.new_line if args.new_line is not None else args.old_line,
    }

    note = api_post(f"/repos/{owner}/{repo}/pulls/{number}/comments", token, payload)
    print(f"Posted inline comment {note['id']} on {owner}/{repo}#PR!{number}")
    print(f"  {args.inline_file}:{payload['line']} ({payload['side']})")
    print(f"  {note['html_url']}")


if __name__ == "__main__":
    main()
