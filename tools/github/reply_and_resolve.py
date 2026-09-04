#!/usr/bin/env python3
"""
Reply to GitHub pull request review threads and optionally mark them resolved.

Used by the fix_review phase: after fixes land, every addressed thread gets a
reply naming the change, and is resolved when the fix is in.

Two APIs are needed, and that is not avoidable. Replying is REST. **Resolving a
review thread exists only in GraphQL** -- the REST API has no equivalent -- so
thread ids here are GraphQL node ids, not the numeric comment ids REST returns.
`--list` prints the right id to use.

Usage:
    reply_and_resolve.py <ref> --list
    reply_and_resolve.py <ref> --plan <plan.json> [--dry-run]
    reply_and_resolve.py <ref> --discussion <thread-id> --body "<text>" [--resolve]

Arguments:
    ref     Full URL or short ref for the PR.
            Short format: khai-nguyen-quang/dash-cam#PR!45
            Full URL:     https://github.com/khai-nguyen-quang/dash-cam/pull/45

Options:
    --list              Print every review thread: id, file:line, state, first line.
    --plan <path>       JSON list of {"discussion_id", "body", "resolve"} entries.
    --discussion <id>   Single thread to reply to (the GraphQL node id from --list).
    --body <text>       Reply body for --discussion.
    --resolve           With --discussion, also mark the thread resolved.
    --dry-run           With --plan, print what would be posted without calling the API.
    --help, -h          Show this help.

Plan file format:
    [
      {"discussion_id": "PRRT_kwDO...", "body": "Fixed in `deadbeef` — ...", "resolve": true},
      {"discussion_id": "PRRT_kwDO...", "body": "Left as is — ...",          "resolve": false}
    ]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _common import api_post, get_token, graphql, resolve_ref  # noqa: E402

THREADS_QUERY = """
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 1) {
            nodes { databaseId body author { login } }
          }
        }
      }
    }
  }
}
"""

RESOLVE_MUTATION = """
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { id isResolved }
  }
}
"""


def fetch_threads(owner: str, repo: str, number: int, token: str) -> list[dict]:
    data = graphql(THREADS_QUERY, token, {"owner": owner, "repo": repo, "number": number})
    pr = ((data.get("repository") or {}).get("pullRequest") or {})
    return ((pr.get("reviewThreads") or {}).get("nodes") or [])


def root_comment_id(thread: dict) -> int | None:
    """The numeric id of a thread's first comment -- REST replies target that."""
    nodes = ((thread.get("comments") or {}).get("nodes") or [])
    return nodes[0].get("databaseId") if nodes else None


def do_reply(owner: str, repo: str, number: int, thread: dict, body: str, token: str) -> None:
    comment_id = root_comment_id(thread)
    if comment_id is None:
        print(f"Error: thread {thread['id']} has no comments to reply to.", file=sys.stderr)
        sys.exit(1)
    api_post(f"/repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies",
             token, {"body": body})


def do_resolve(thread_id: str, token: str) -> bool:
    data = graphql(RESOLVE_MUTATION, token, {"threadId": thread_id})
    return bool((((data.get("resolveReviewThread") or {}).get("thread")) or {}).get("isResolved"))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Reply to and resolve GitHub PR review threads.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("ref", help="PR ref (short or full URL)")
    parser.add_argument("--list", action="store_true", dest="do_list")
    parser.add_argument("--plan", metavar="PATH")
    parser.add_argument("--discussion", metavar="ID")
    parser.add_argument("--body", metavar="TEXT")
    parser.add_argument("--resolve", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    token = get_token()
    kind, owner, repo, number = resolve_ref(args.ref)
    if kind != "mr":
        print(f"Error: ref '{args.ref}' is an issue, not a pull request.", file=sys.stderr)
        sys.exit(1)

    if args.do_list:
        threads = fetch_threads(owner, repo, number, token)
        if not threads:
            print("(no review threads)")
            return
        print(f"{len(threads)} review thread(s) on {owner}/{repo}#PR!{number}\n")
        for t in threads:
            comments = ((t.get("comments") or {}).get("nodes") or [])
            first = comments[0] if comments else {}
            author = (first.get("author") or {}).get("login", "?")
            summary = (first.get("body") or "").strip().splitlines()
            state = "resolved" if t.get("isResolved") else "unresolved"
            if t.get("isOutdated"):
                state += ", outdated"
            print(f"  {t['id']}")
            print(f"    {t.get('path') or '(no file)'}:{t.get('line') or '?'}  [{state}]  {author}")
            print(f"    {summary[0][:80] if summary else '(empty)'}")
        return

    if args.plan:
        entries = json.loads(Path(args.plan).read_text())
        threads = {t["id"]: t for t in fetch_threads(owner, repo, number, token)}
        for entry in entries:
            tid = entry["discussion_id"]
            body = entry["body"]
            resolve = bool(entry.get("resolve"))
            if args.dry_run:
                print(f"DRY RUN {tid}  resolve={resolve}")
                print(f"  {body.strip().splitlines()[0][:80] if body.strip() else '(empty)'}")
                continue
            thread = threads.get(tid)
            if thread is None:
                print(f"Error: thread '{tid}' is not on this pull request.", file=sys.stderr)
                sys.exit(1)
            do_reply(owner, repo, number, thread, body, token)
            if resolve:
                ok = do_resolve(tid, token)
                print(f"replied and {'resolved' if ok else 'FAILED TO RESOLVE'}  {tid}")
            else:
                print(f"replied            {tid}")
        return

    if args.discussion:
        if not args.body:
            print("Error: --discussion needs --body.", file=sys.stderr)
            sys.exit(1)
        threads = {t["id"]: t for t in fetch_threads(owner, repo, number, token)}
        thread = threads.get(args.discussion)
        if thread is None:
            print(f"Error: thread '{args.discussion}' is not on this pull request.", file=sys.stderr)
            print("  Run --list to see the thread ids.", file=sys.stderr)
            sys.exit(1)
        do_reply(owner, repo, number, thread, args.body, token)
        if args.resolve:
            ok = do_resolve(args.discussion, token)
            print(f"replied and {'resolved' if ok else 'FAILED TO RESOLVE'}  {args.discussion}")
        else:
            print(f"replied            {args.discussion}")
        return

    print("Error: one of --list, --plan or --discussion is required.", file=sys.stderr)
    parser.print_help(sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
