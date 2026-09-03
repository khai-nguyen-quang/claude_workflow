#!/usr/bin/env python3
"""
Reply to GitLab MR discussion threads and optionally mark them resolved.

Used by the fix_review phase: after fixes land, every addressed thread gets a
reply naming the change, and is resolved when the fix is in.

Usage:
    reply_and_resolve.py <ref> --list
    reply_and_resolve.py <ref> --plan <plan.json> [--dry-run]
    reply_and_resolve.py <ref> --discussion <id> --body "<text>" [--resolve]

Arguments:
    ref     Full URL or short ref for the MR.
            Short format: projectX#MR!177
            Full URL:     https://gitlab.company.com/.../merge_requests/177

Options:
    --list              Print every resolvable thread: id, file:line, state, first line.
    --plan <path>       JSON list of {"discussion_id", "body", "resolve"} entries.
    --discussion <id>   Single thread to reply to.
    --body <text>       Reply body for --discussion.
    --resolve           With --discussion, also mark the thread resolved.
    --dry-run           With --plan, print what would be posted without calling the API.
    --help, -h          Show this help.

Plan file format:
    [
      {"discussion_id": "abc123", "body": "Fixed in `deadbeef` — ...", "resolve": true},
      {"discussion_id": "def456", "body": "Left as is — ...",          "resolve": false}
    ]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import api_get_paged, api_post, api_put, encode_project, get_token, resolve_ref


def fetch_threads(encoded: str, iid: int, token: str) -> list[dict]:
    """Return resolvable (non-system) discussion threads for the MR."""
    threads = api_get_paged(f"/projects/{encoded}/merge_requests/{iid}/discussions", token)
    out = []
    for disc in threads:
        notes = disc.get("notes") or []
        if not notes:
            continue
        first = notes[0]
        if first.get("system") or not first.get("resolvable"):
            continue
        out.append(disc)
    return out


def describe(disc: dict) -> str:
    """One-line summary of a thread for --list output."""
    first = (disc.get("notes") or [{}])[0]
    pos = first.get("position") or {}
    path = pos.get("new_path") or pos.get("old_path") or "-"
    line = pos.get("new_line") or pos.get("old_line") or "-"
    state = "resolved" if first.get("resolved") else "OPEN"
    head = (first.get("body") or "").splitlines()[0][:70]
    return f"{disc['id']}  {state:8}  {path}:{line}  {head}"


def reply(encoded: str, iid: int, token: str, disc_id: str, body: str) -> int:
    result = api_post(
        f"/projects/{encoded}/merge_requests/{iid}/discussions/{disc_id}/notes",
        token,
        {"body": body},
    )
    return result.get("id")


def resolve(encoded: str, iid: int, token: str, disc_id: str) -> None:
    api_put(
        f"/projects/{encoded}/merge_requests/{iid}/discussions/{disc_id}",
        token,
        {"resolved": True},
    )


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("ref")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--plan")
    parser.add_argument("--discussion")
    parser.add_argument("--body")
    parser.add_argument("--resolve", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--help", "-h", action="store_true")
    args = parser.parse_args()

    if args.help:
        print(__doc__)
        return 0

    kind, project, iid = resolve_ref(args.ref)
    if kind != "mr":
        print(f"Error: {args.ref} is not a merge request ref.", file=sys.stderr)
        return 1

    token = get_token()
    encoded = encode_project(project)

    if args.list:
        for disc in fetch_threads(encoded, iid, token):
            print(describe(disc))
        return 0

    if args.discussion:
        if not args.body:
            print("Error: --discussion requires --body.", file=sys.stderr)
            return 1
        note_id = reply(encoded, iid, token, args.discussion, args.body)
        print(f"Replied to {args.discussion} (note {note_id}).")
        if args.resolve:
            resolve(encoded, iid, token, args.discussion)
            print(f"Resolved {args.discussion}.")
        return 0

    if args.plan:
        entries = json.loads(Path(args.plan).read_text())
        for entry in entries:
            disc_id = entry["discussion_id"]
            body = entry["body"]
            want_resolve = entry.get("resolve", False)
            if args.dry_run:
                flag = " +resolve" if want_resolve else ""
                print(f"[dry-run]{flag} {disc_id}: {body.splitlines()[0][:70]}")
                continue
            note_id = reply(encoded, iid, token, disc_id, body)
            if want_resolve:
                resolve(encoded, iid, token, disc_id)
            print(f"{disc_id}: note {note_id}{' + resolved' if want_resolve else ''}")
        print(f"\n{len(entries)} thread(s) processed.")
        return 0

    print("Error: pass one of --list, --plan, or --discussion.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
