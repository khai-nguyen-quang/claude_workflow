#!/usr/bin/env bash
# Fetch and switch to the source branch of a GitLab MR.
#
# Usage:
#   checkout_mr_branch.sh <mr-ref>
#
# Examples:
#   checkout_mr_branch.sh projectX#MR!177
#   checkout_mr_branch.sh https://gitlab.company.com/.../merge_requests/177

set -euo pipefail

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# shellcheck source=claude_workflow/tools/gitlab/_env.sh
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

_show_help() {
  cat << 'EOF'
Usage: checkout_mr_branch.sh <mr-ref> [options]

Fetches the remote source branch of a GitLab MR and switches to it locally.

Arguments:
  mr-ref    Short ref (projectX#MR!177) or full MR URL.

Options:
  --remote <name>  Git remote to fetch from. Defaults to "origin".
  --no-switch      Fetch the branch without switching to it.
  --help, -h       Show this help.

Examples:
  checkout_mr_branch.sh projectX#MR!177
  checkout_mr_branch.sh projectX#MR!177 --remote origin
  checkout_mr_branch.sh https://gitlab.company.com/.../merge_requests/177
EOF
}

mr_ref=""
remote="origin"
do_switch=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)    remote="$2"; shift 2 ;;
    --no-switch) do_switch=false; shift ;;
    --help|-h)   _show_help; exit 0 ;;
    --*)         echo "Error: unknown flag '$1'" >&2; _show_help; exit 1 ;;
    *)
      if [[ -z "${mr_ref}" ]]; then mr_ref="$1"; shift
      else echo "Error: unexpected argument '$1'" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -z "${mr_ref}" ]]; then
  echo "Error: mr-ref is required." >&2
  _show_help; exit 1
fi

# Parse ref
ref_parts="$(resolve_ref "${mr_ref}")"
kind="$(echo "${ref_parts}" | cut -d' ' -f1)"
project_path="$(echo "${ref_parts}" | cut -d' ' -f2)"
iid="$(echo "${ref_parts}" | cut -d' ' -f3)"

if [[ "${kind}" != "mr" ]]; then
  echo "Error: '${mr_ref}' is an issue, not a merge request." >&2
  echo "  Use branch/create_branch.sh for issues." >&2
  exit 1
fi

# Fetch MR metadata
encoded="$(url_encode "${project_path}")"
mr_json="$(api_get "/projects/${encoded}/merge_requests/${iid}")"

{
  read -r source_branch
  read -r target_branch
  read -r mr_state
  read -r mr_title
} < <(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
print(d['source_branch'])
print(d['target_branch'])
print(d['state'])
print(d['title'])
" "${mr_json}")

echo "MR !${iid}: ${mr_title}"
echo "State:  ${mr_state}"
echo "Branch: ${source_branch}  →  ${target_branch}"
echo ""

project_name="$(basename "${project_path}")"
REPO_ROOT="${WORKSPACE_ROOT}/${project_name}"

if [[ ! -d "${REPO_ROOT}/.git" ]]; then
  echo "Error: local repo not found at '${REPO_ROOT}'." >&2
  exit 1
fi

cd "${REPO_ROOT}"

# Fetch the branch from remote
echo "Fetching ${remote}/${source_branch}..."
git fetch "${remote}" "${source_branch}"

if ! "${do_switch}"; then
  echo "Fetched (not switched)."
  exit 0
fi

# Switch: checkout existing local branch or create a tracking branch
if git show-ref --quiet "refs/heads/${source_branch}"; then
  echo "Local branch '${source_branch}' exists — switching and pulling."
  git checkout "${source_branch}"
  git pull "${remote}" "${source_branch}"
else
  echo "Creating local tracking branch '${source_branch}'."
  git checkout -b "${source_branch}" "${remote}/${source_branch}"
fi

echo ""
echo "Now on branch '${source_branch}'."
