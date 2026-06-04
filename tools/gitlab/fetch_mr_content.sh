#!/usr/bin/env bash
# Fetch a GitLab MR: metadata, description, diff, and discussion notes.
#
# Usage:
#   fetch_mr_content.sh <ref> [--diff] [--notes] [--json]
#
# Examples:
#   fetch_mr_content.sh projectX#MR!177
#   fetch_mr_content.sh projectX#MR!177 --diff
#   fetch_mr_content.sh https://gitlab.company.com/.../merge_requests/177 --notes

set -euo pipefail

# shellcheck source=tools/gitlab/_env.sh
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

_show_help() {
  cat << 'EOF'
Usage: fetch_mr_content.sh <ref> [options]

Fetches MR metadata, description, diff, and discussion notes.

Arguments:
  ref       Full URL or short ref.
            Short format: projectX#MR!177
            Full URL:     https://gitlab.company.com/.../merge_requests/177

Options:
  --diff    Include the unified diff of all changed files.
  --notes   Include discussion notes/comments.
  --json    Output raw JSON (one object with keys: mr, changes, notes).
  --help,-h Show this help.

Output sections (default: metadata + description only):
  [MR]        Title, state, author, branches, URL
  [DIFF]      Unified diff of changed files (with --diff)
  [NOTES]     Discussion threads (with --notes)
EOF
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

# Parse ref
ref_parts="$(resolve_ref "${ref}")"
kind="$(echo "${ref_parts}" | cut -d' ' -f1)"
project_path="$(echo "${ref_parts}" | cut -d' ' -f2)"
iid="$(echo "${ref_parts}" | cut -d' ' -f3)"

if [[ "${kind}" != "mr" ]]; then
  echo "Error: ref '${ref}' is an issue, not a merge request." >&2
  echo "  Use fetch_ticket_description.py for issues." >&2
  exit 1
fi

encoded="$(url_encode "${project_path}")"

# Write API responses to temp files to avoid control-character issues in heredocs
tmp_dir="$(mktemp -d)"
cleanup() { rm -rf "${tmp_dir}"; }
trap cleanup EXIT

api_get "/projects/${encoded}/merge_requests/${iid}" > "${tmp_dir}/mr.json"

if "${show_diff}"; then
  api_get "/projects/${encoded}/merge_requests/${iid}/changes" > "${tmp_dir}/changes.json"
else
  echo '{}' > "${tmp_dir}/changes.json"
fi

if "${show_notes}"; then
  api_get "/projects/${encoded}/merge_requests/${iid}/notes?sort=asc&per_page=100" > "${tmp_dir}/notes.json"
else
  echo '[]' > "${tmp_dir}/notes.json"
fi

# JSON mode: merge and dump
if "${as_json}"; then
  python3 - "${tmp_dir}/mr.json" "${tmp_dir}/changes.json" "${tmp_dir}/notes.json" << 'PYEOF'
import json, sys
mr      = json.load(open(sys.argv[1]))
changes = json.load(open(sys.argv[2]))
notes   = json.load(open(sys.argv[3]))
print(json.dumps({"mr": mr, "changes": changes, "notes": notes}, indent=2))
PYEOF
  exit 0
fi

# Human-readable output
python3 - "${tmp_dir}/mr.json" "${tmp_dir}/changes.json" "${tmp_dir}/notes.json" \
          "${project_path}" "${show_diff}" "${show_notes}" << 'PYEOF'
import json, sys

mr           = json.load(open(sys.argv[1]))
changes      = json.load(open(sys.argv[2]))
notes        = json.load(open(sys.argv[3]))
project_path = sys.argv[4]
show_diff    = sys.argv[5] == "true"
show_notes   = sys.argv[6] == "true"

title     = mr.get("title", "")
state     = mr.get("state", "")
author    = (mr.get("author") or {}).get("name", "unknown")
created   = (mr.get("created_at") or "")[:10]
updated   = (mr.get("updated_at") or "")[:10]
src       = mr.get("source_branch", "")
dst       = mr.get("target_branch", "")
url       = mr.get("web_url", "")
desc      = mr.get("description") or "(no description)"
assignees = ", ".join(a.get("name", "") for a in (mr.get("assignees") or [])) or "(none)"
labels    = ", ".join(mr.get("labels") or []) or "(none)"
sha       = mr.get("sha", "")[:8]

print(f"MR !{mr.get('iid')} — {title}")
print("─" * 70)
print(f"Project:    {project_path}")
print(f"State:      {state}")
print(f"Author:     {author}  ({created})")
print(f"Updated:    {updated}")
print(f"Branches:   {src}  →  {dst}")
print(f"SHA:        {sha}")
print(f"Assignees:  {assignees}")
print(f"Labels:     {labels}")
print(f"URL:        {url}")
print()
print("Description:")
print("─" * 70)
print(desc)

if show_diff:
    diffs = changes.get("changes") or changes.get("diffs") or []
    if diffs:
        print()
        print("─" * 70)
        print(f"DIFF  ({len(diffs)} file(s) changed)")
        print("─" * 70)
        for f in diffs:
            old = f.get("old_path", "")
            new = f.get("new_path", "")
            print(f"\n--- {old}" if old == new else f"\n--- {old}  →  {new}")
            diff_text = f.get("diff", "")
            if diff_text:
                print(diff_text, end="")
    else:
        print("\n(no diff available)")

if show_notes:
    visible = [n for n in notes if not n.get("system", False)]
    if visible:
        print()
        print("─" * 70)
        print(f"NOTES  ({len(visible)} comment(s))")
        print("─" * 70)
        for n in visible:
            who  = (n.get("author") or {}).get("name", "?")
            when = (n.get("created_at") or "")[:16].replace("T", " ")
            body = n.get("body", "").strip()
            print(f"\n[{when}] {who}:")
            for line in body.splitlines():
                print(f"  {line}")
    else:
        print("\n(no comments)")
PYEOF
