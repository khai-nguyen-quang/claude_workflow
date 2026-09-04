#!/usr/bin/env bash
# Fetch and switch to the head branch of a GitHub pull request.
#
# Usage:
#   checkout_mr_branch.sh <pr-ref>
#
# Examples:
#   checkout_mr_branch.sh khai-nguyen-quang/dash-cam#PR!45
#   checkout_mr_branch.sh https://github.com/khai-nguyen-quang/dash-cam/pull/45

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=tools/github/_env.sh
source "${SCRIPT_DIR}/_env.sh"
# shellcheck source=tools/gitlab/_repo.sh
source "${SCRIPT_DIR}/_repo.sh"

_show_help() {
  cat << 'HELP'
Usage: checkout_mr_branch.sh <pr-ref> [options]

Fetches the head branch of a GitHub pull request and switches to it locally.

Arguments:
  pr-ref    Short ref (owner/repo#PR!45) or full pull request URL.

Options:
  --remote <name>  Git remote to fetch from. Defaults to "origin".
  --no-switch      Fetch the branch without switching to it.
  --repo <path>    Repository to operate on. Defaults to $WF_REPO, else the repo
                   of the current directory, else $WORKSPACE_ROOT/<repo-name>.
  --help, -h       Show this help.

A pull request opened from a fork has no branch in this repository, so the head
is fetched through refs/pull/<n>/head into a local branch instead.
HELP
}

pr_ref=""
remote="origin"
repo_opt=""
do_switch=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)    remote="$2"; shift 2 ;;
    --repo)      repo_opt="$2"; shift 2 ;;
    --no-switch) do_switch=false; shift ;;
    --help|-h)   _show_help; exit 0 ;;
    --*)         echo "Error: unknown flag '$1'" >&2; _show_help; exit 1 ;;
    *)
      if [[ -z "${pr_ref}" ]]; then pr_ref="$1"; shift
      else echo "Error: unexpected argument '$1'" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -z "${pr_ref}" ]]; then
  echo "Error: pr-ref is required." >&2
  _show_help; exit 1
fi

ref_parts="$(resolve_ref "${pr_ref}")"
kind="$(echo "${ref_parts}" | cut -d' ' -f1)"
owner="$(echo "${ref_parts}" | cut -d' ' -f2)"
repo="$(echo "${ref_parts}" | cut -d' ' -f3)"
number="$(echo "${ref_parts}" | cut -d' ' -f4)"

if [[ "${kind}" != "mr" ]]; then
  echo "Error: '${pr_ref}' is an issue, not a pull request." >&2
  echo "  Use branch/create_branch.sh for issues." >&2
  exit 1
fi

pr_json="$(api_get "/repos/${owner}/${repo}/pulls/${number}")"

{
  read -r head_branch
  read -r base_branch
  read -r pr_state
  read -r is_fork
  read -r pr_title
} < <(python3 -c "
import json, sys
d = json.loads(sys.argv[1])
head = d.get('head') or {}
base = d.get('base') or {}
print(head.get('ref', ''))
print(base.get('ref', ''))
print(d.get('state', ''))
print('true' if (head.get('repo') or {}).get('full_name') != d['base']['repo']['full_name'] else 'false')
print(d.get('title', ''))
" "${pr_json}")

echo "PR #${number}: ${pr_title}"
echo "State:  ${pr_state}"
echo "Branch: ${head_branch}  →  ${base_branch}"
echo ""

if [[ -z "${repo_opt}" && -z "${WF_REPO:-}" ]] && ! git -C "${PWD}" rev-parse --git-dir &>/dev/null; then
  repo_opt="${WORKSPACE_ROOT}/${repo}"
fi
REPO_ROOT="$(resolve_repo_root "${WORKSPACE_ROOT}" "${repo_opt}")"

cd "${REPO_ROOT}"
echo "Repo:   ${REPO_ROOT}"

if [[ "${is_fork}" == "true" ]]; then
  # A fork's branch does not exist in this remote; refs/pull/<n>/head always does.
  local_branch="pr-${number}"
  echo "Pull request comes from a fork — fetching refs/pull/${number}/head as '${local_branch}'."
  git fetch "${remote}" "refs/pull/${number}/head:${local_branch}" --force
else
  local_branch="${head_branch}"
  echo "Fetching ${remote}/${head_branch}..."
  git fetch "${remote}" "${head_branch}"
fi

if ! "${do_switch}"; then
  echo "Fetched (not switched)."
  exit 0
fi

if [[ "${is_fork}" == "true" ]]; then
  git checkout "${local_branch}"
elif git show-ref --quiet "refs/heads/${local_branch}"; then
  echo "Local branch '${local_branch}' exists — switching and pulling."
  git checkout "${local_branch}"
  git pull "${remote}" "${local_branch}"
else
  echo "Creating local tracking branch '${local_branch}'."
  git checkout -b "${local_branch}" "${remote}/${local_branch}"
fi

echo ""
echo "Now on branch '${local_branch}'."
