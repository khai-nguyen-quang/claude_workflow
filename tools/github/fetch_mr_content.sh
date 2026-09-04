#!/usr/bin/env bash
# Fetch a GitHub pull request: metadata, description, diff, and comments.
#
# Named fetch_mr_content.sh to match its GitLab counterpart: the workflow's
# operation vocabulary is shared across forges, and MR == PR.
#
# Usage:
#   fetch_mr_content.sh <ref> [--diff] [--notes] [--json]
#
# Examples:
#   fetch_mr_content.sh khai-nguyen-quang/dash-cam#PR!45
#   fetch_mr_content.sh khai-nguyen-quang/dash-cam#PR!45 --diff
#   fetch_mr_content.sh https://github.com/khai-nguyen-quang/dash-cam/pull/45 --notes

set -euo pipefail

# shellcheck source=tools/github/_env.sh
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

_show_help() {
  cat << 'HELP'
Usage: fetch_mr_content.sh <ref> [options]

Fetches pull request metadata, description, diff, and comments.

Arguments:
  ref       Full URL or short ref.
            Short format: owner/repo#PR!45
            Full URL:     https://github.com/owner/repo/pull/45

Options:
  --diff    Include the unified diff of all changed files.
  --notes   Include review comments, review summaries and issue comments.
  --json    Output raw JSON (one object with keys: mr, changes, notes).
  --help,-h Show this help.

Output sections (default: metadata + description only):
  [PR]        Title, state, author, branches, URL
  [DIFF]      Unified diff of changed files (with --diff)
  [NOTES]     Comments and reviews (with --notes)
HELP
}

show_diff=false
show_notes=false
as_json=false
ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --diff)     show_diff=true; shift ;;
    --notes)    show_notes=true; shift ;;
    --json)     as_json=true; shift ;;
    --help|-h)  _show_help; exit 0 ;;
    --*)        echo "Error: unknown flag '$1'" >&2; _show_help; exit 1 ;;
    *)
      if [[ -z "${ref}" ]]; then ref="$1"; shift
      else echo "Error: unexpected argument '$1'" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -z "${ref}" ]]; then
  echo "Error: ref is required." >&2
  _show_help
  exit 1
fi

ref_parts="$(resolve_ref "${ref}")"
kind="$(echo "${ref_parts}" | cut -d' ' -f1)"
owner="$(echo "${ref_parts}" | cut -d' ' -f2)"
repo="$(echo "${ref_parts}" | cut -d' ' -f3)"
number="$(echo "${ref_parts}" | cut -d' ' -f4)"

if [[ "${kind}" != "mr" ]]; then
  echo "Error: ref '${ref}' is an issue, not a pull request." >&2
  echo "  Use fetch_ticket_description.py for issues." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "${tmp_dir}"; }
trap cleanup EXIT

api_get "/repos/${owner}/${repo}/pulls/${number}" > "${tmp_dir}/pr.json"

if "${show_diff}"; then
  api_get "/repos/${owner}/${repo}/pulls/${number}/files?per_page=100" > "${tmp_dir}/files.json"
else
  echo '[]' > "${tmp_dir}/files.json"
fi

if "${show_notes}"; then
  # Three separate streams on GitHub: inline review comments, review summaries,
  # and plain issue comments on the PR conversation.
  api_get "/repos/${owner}/${repo}/pulls/${number}/comments?per_page=100"  > "${tmp_dir}/review_comments.json"
  api_get "/repos/${owner}/${repo}/pulls/${number}/reviews?per_page=100"   > "${tmp_dir}/reviews.json"
  api_get "/repos/${owner}/${repo}/issues/${number}/comments?per_page=100" > "${tmp_dir}/issue_comments.json"
else
  echo '[]' > "${tmp_dir}/review_comments.json"
  echo '[]' > "${tmp_dir}/reviews.json"
  echo '[]' > "${tmp_dir}/issue_comments.json"
fi

if "${as_json}"; then
  python3 - "${tmp_dir}" << 'PYEOF'
import json, sys, pathlib
d = pathlib.Path(sys.argv[1])
load = lambda n: json.loads((d / n).read_text())
print(json.dumps({
    "mr": load("pr.json"),
    "changes": load("files.json"),
    "notes": {
        "review_comments": load("review_comments.json"),
        "reviews": load("reviews.json"),
        "issue_comments": load("issue_comments.json"),
    },
}, indent=2))
PYEOF
  exit 0
fi

python3 - "${tmp_dir}" "${owner}/${repo}" "${show_diff}" "${show_notes}" << 'PYEOF'
import json, sys, pathlib

d          = pathlib.Path(sys.argv[1])
repo_full  = sys.argv[2]
show_diff  = sys.argv[3] == "true"
show_notes = sys.argv[4] == "true"
load = lambda n: json.loads((d / n).read_text())

pr = load("pr.json")

state = pr.get("state", "")
if pr.get("draft"):
    state += " (draft)"
if pr.get("merged"):
    state = "merged"

print(f"PR #{pr.get('number')} — {pr.get('title', '')}")
print("─" * 70)
print(f"Repository: {repo_full}")
print(f"State:      {state}")
print(f"Author:     {(pr.get('user') or {}).get('login', 'unknown')}  ({(pr.get('created_at') or '')[:10]})")
print(f"Updated:    {(pr.get('updated_at') or '')[:10]}")
print(f"Branches:   {(pr.get('head') or {}).get('ref', '')}  →  {(pr.get('base') or {}).get('ref', '')}")
print(f"SHA:        {((pr.get('head') or {}).get('sha') or '')[:8]}")
print(f"Assignees:  {', '.join(a.get('login', '') for a in (pr.get('assignees') or [])) or '(none)'}")
print(f"Labels:     {', '.join(l.get('name', '') for l in (pr.get('labels') or [])) or '(none)'}")
print(f"Changes:    +{pr.get('additions', 0)} -{pr.get('deletions', 0)} in {pr.get('changed_files', 0)} file(s)")
print(f"URL:        {pr.get('html_url', '')}")
print()
print("Description:")
print("─" * 70)
print(pr.get("body") or "(no description)")

if show_diff:
    files = load("files.json")
    if files:
        print()
        print("─" * 70)
        print(f"DIFF  ({len(files)} file(s) changed)")
        print("─" * 70)
        for f in files:
            old, new = f.get("previous_filename"), f.get("filename", "")
            print(f"\n--- {old}  →  {new}" if old else f"\n--- {new}")
            patch = f.get("patch")
            if patch:
                print(patch)
            else:
                # Binary files, and files above GitHub's per-file patch limit,
                # come back with no patch at all.
                print(f"  ({f.get('status', 'changed')}, no inline patch available)")
    else:
        print("\n(no diff available)")

if show_notes:
    review_comments = load("review_comments.json")
    reviews         = [r for r in load("reviews.json") if (r.get("body") or "").strip()]
    issue_comments  = load("issue_comments.json")
    total = len(review_comments) + len(reviews) + len(issue_comments)

    print()
    print("─" * 70)
    print(f"NOTES  ({total} comment(s))")
    print("─" * 70)

    if not total:
        print("\n(no comments)")

    for c in review_comments:
        who  = (c.get("user") or {}).get("login", "?")
        when = (c.get("created_at") or "")[:16].replace("T", " ")
        loc  = f"{c.get('path', '')}:{c.get('line') or c.get('original_line') or '?'}"
        print(f"\n[{when}] {who} — inline {loc}  (comment id {c.get('id')})")
        for line in (c.get("body") or "").strip().splitlines():
            print(f"  {line}")

    for r in reviews:
        who  = (r.get("user") or {}).get("login", "?")
        when = (r.get("submitted_at") or "")[:16].replace("T", " ")
        print(f"\n[{when}] {who} — review {r.get('state', '')}")
        for line in (r.get("body") or "").strip().splitlines():
            print(f"  {line}")

    for c in issue_comments:
        who  = (c.get("user") or {}).get("login", "?")
        when = (c.get("created_at") or "")[:16].replace("T", " ")
        print(f"\n[{when}] {who}:")
        for line in (c.get("body") or "").strip().splitlines():
            print(f"  {line}")
PYEOF
