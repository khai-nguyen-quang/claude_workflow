#!/usr/bin/env bash
# Create and checkout a new git branch for a GitHub issue.
# Branch name convention: feature/<slug>-<issue-number> or bug/<slug>-<issue-number>
#
# Usage:
#   create_branch.sh <issue-ref> [--name <branch-name>] [--type <feature|bug>]
#
# Examples:
#   create_branch.sh khai-nguyen-quang/dash-cam#12
#   create_branch.sh khai-nguyen-quang/dash-cam#12 --name recorder-pipeline
#   create_branch.sh khai-nguyen-quang/dash-cam#12 --type bug

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=tools/github/_env.sh
source "${SCRIPT_DIR}/../_env.sh"
# shellcheck source=tools/gitlab/_repo.sh
source "${SCRIPT_DIR}/../_repo.sh"

_show_help() {
  cat << 'HELP'
Usage: create_branch.sh <issue-ref> [options]

Creates and checks out a new git branch for a GitHub issue.
Branch name: <type>/<slug>-<issue-number>  (e.g. feature/recorder-pipeline-12)

Arguments:
  issue-ref    Short ref (owner/repo#12) or full GitHub issue URL.

Options:
  --name <slug>      Custom slug for the branch name (spaces → hyphens).
                     If omitted, the issue title is fetched and slugified.
  --type <type>      Branch prefix: feature or bug. Default: feature.
  --no-checkout      Create the branch without switching to it.
  --repo <path>      Repository to operate on. Defaults to $WF_REPO, else the
                     repo of the current directory, else the sole repo under
                     the workspace.
  --help, -h         Show this help.

Note: when a ticket has its own worktree (tools/git/worktree.sh, which the /wf
skill runs automatically), the branch is created with the worktree and this
script is not needed. Use it for standalone / free-form branch creation.
HELP
}

issue_ref=""
branch_slug=""
repo_opt=""
branch_type="feature"
checkout=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)        branch_slug="$2"; shift 2 ;;
    --repo)        repo_opt="$2"; shift 2 ;;
    --type)        branch_type="$2"; shift 2 ;;
    --no-checkout) checkout=false; shift ;;
    --help|-h)     _show_help; exit 0 ;;
    --*)           echo "Error: unknown flag '$1'" >&2; _show_help; exit 1 ;;
    *)
      if [[ -z "${issue_ref}" ]]; then issue_ref="$1"; shift
      else echo "Error: unexpected argument '$1'" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -z "${issue_ref}" ]]; then
  echo "Error: issue-ref is required." >&2
  _show_help; exit 1
fi

case "${branch_type}" in
  feature|bug) ;;
  *) echo "Error: --type must be feature or bug (got '${branch_type}')" >&2; exit 1 ;;
esac

ref_parts="$(resolve_ref "${issue_ref}")"
kind="$(echo "${ref_parts}" | cut -d' ' -f1)"
owner="$(echo "${ref_parts}" | cut -d' ' -f2)"
repo="$(echo "${ref_parts}" | cut -d' ' -f3)"
number="$(echo "${ref_parts}" | cut -d' ' -f4)"

if [[ "${kind}" != "issue" ]]; then
  echo "Error: '${issue_ref}' is a pull request, not an issue." >&2
  exit 1
fi

if [[ -z "${repo_opt}" && -z "${WF_REPO:-}" ]] && ! git -C "${PWD}" rev-parse --git-dir &>/dev/null; then
  repo_opt="${WORKSPACE_ROOT}/${repo}"
fi
REPO_ROOT="$(resolve_repo_root "${WORKSPACE_ROOT}" "${repo_opt}")"

if [[ -z "${branch_slug}" ]]; then
  title="$(api_get "/repos/${owner}/${repo}/issues/${number}" | \
    python3 -c "import json,sys; print(json.load(sys.stdin)['title'])")"
  branch_slug="$(echo "${title}" | python3 -c "
import sys, re
s = sys.stdin.read().strip().lower()
s = re.sub(r'[^a-z0-9]+', '-', s)
s = s.strip('-')[:40].rstrip('-')
print(s)
")"
fi

branch_name="${branch_type}/${branch_slug}-${number}"

cd "${REPO_ROOT}"

if git show-ref --quiet "refs/heads/${branch_name}"; then
  echo "Error: branch '${branch_name}' already exists." >&2
  exit 1
fi

echo "Creating branch: ${branch_name}"
git branch "${branch_name}"

if "${checkout}"; then
  git checkout "${branch_name}"
  echo "Switched to branch '${branch_name}'."
else
  echo "Branch created (not checked out)."
fi
