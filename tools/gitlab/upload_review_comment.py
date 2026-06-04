#!/usr/bin/env python3
"""
Post a review comment (note) on a GitLab MR.

Usage:
    upload_review_comment.py <ref> <body>
    upload_review_comment.py <ref> --file <comment.txt>
    upload_review_comment.py <ref> - < comment.txt          (read body from stdin)

    # Inline comment on a specific file/line:
    upload_review_comment.py <ref> <body> --inline-file <path> --new-line <N> [--sha <commit_sha>]

Arguments:
    ref     Full URL or short ref for the MR.
            Short format: projectX#MR!177
            Full URL:     https://gitlab.company.com/.../merge_requests/177

Options:
    --file <path>         Read comment body from a file instead of argv.
    --inline-file <path>  File path (in the repo) for an inline comment.
    --new-line <N>        Line number on the new side for an inline comment.
    --old-line <N>        Line number on the old side (optional, for context lines).
    --sha <sha>           Commit SHA for inline comments (defaults to MR head SHA).
    --help, -h            Show this help.

Examples:
    ./upload_review_comment.py projectX#MR!177 "LGTM, nice refactor."
    ./upload_review_comment.py projectX#MR!177 --file review.txt
    ./upload_review_comment.py projectX#MR!177 "Fix null check here" \\
        --inline-file system/camerad/cameras/camera_rk.cc --new-line 42
"""

from __future__ import annotations

import argparse
import sys

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from _common import api_get, api_post, encode_project, get_token, resolve_ref


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Post a review comment on a GitLab MR.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("ref", help="MR ref (short or full URL)")
    parser.add_argument("body", nargs="?", default=None, help="Comment body (or '-' for stdin)")
    parser.add_argument("--file", metavar="PATH", help="Read body from file")
    parser.add_argument("--inline-file", metavar="PATH", help="Repo file path for inline comment")
    parser.add_argument("--new-line", type=int, metavar="N", help="New-side line number for inline comment")
    parser.add_argument("--old-line", type=int, metavar="N", help="Old-side line number for inline comment")
    parser.add_argument("--sha", help="Commit SHA for inline comment (defaults to MR head SHA)")
    args = parser.parse_args()

    # Resolve comment body
    if args.file:
        from pathlib import Path
        body = Path(args.file).read_text()
    elif args.body == "-" or args.body is None and not sys.stdin.isatty():
        body = sys.stdin.read()
    elif args.body:
        body = args.body
    else:
        parser.print_help(sys.stderr)
        print("\nError: comment body is required (argument, --file, or stdin).", file=sys.stderr)
        sys.exit(1)

    body = body.strip()
    if not body:
        print("Error: comment body is empty.", file=sys.stderr)
        sys.exit(1)

    token = get_token()
    kind, project_path, iid = resolve_ref(args.ref)

    if kind != "mr":
        print(f"Error: ref '{args.ref}' is an issue, not a merge request.", file=sys.stderr)
        sys.exit(1)

    encoded = encode_project(project_path)

    # Inline comment: use the discussions API with position
    if args.inline_file:
        if not args.new_line:
            print("Error: --new-line is required for inline comments.", file=sys.stderr)
            sys.exit(1)

        # Resolve SHA
        sha = args.sha
        if not sha:
            mr_data = api_get(f"/projects/{encoded}/merge_requests/{iid}", token)
            sha = mr_data.get("sha") or mr_data.get("diff_refs", {}).get("head_sha", "")
            if not sha:
                print("Error: could not determine MR head SHA. Pass --sha explicitly.", file=sys.stderr)
                sys.exit(1)

        mr_data = api_get(f"/projects/{encoded}/merge_requests/{iid}", token)
        diff_refs = mr_data.get("diff_refs") or {}
        base_sha = diff_refs.get("base_sha", "")
        start_sha = diff_refs.get("start_sha", "")

        position: dict = {
            "position_type": "text",
            "new_path": args.inline_file,
            "old_path": args.inline_file,
            "new_line": args.new_line,
            "head_sha": sha,
            "base_sha": base_sha,
            "start_sha": start_sha,
        }
        if args.old_line:
            position["old_line"] = args.old_line

        payload = {"body": body, "position": position}
        result = api_post(f"/projects/{encoded}/merge_requests/{iid}/discussions", token, payload)
        note_id = result.get("notes", [{}])[0].get("id", "?")
        print(f"Inline comment posted (discussion note {note_id}).")

    else:
        # Regular MR note
        payload = {"body": body}
        result = api_post(f"/projects/{encoded}/merge_requests/{iid}/notes", token, payload)
        note_id = result.get("id", "?")
        web_url = result.get("noteable_web_url") or ""
        print(f"Comment posted (note {note_id}).")
        if web_url:
            print(f"URL: {web_url}")


if __name__ == "__main__":
    main()
