#!/usr/bin/env bash
# Push the current (or specified) branch to its remote, setting upstream if needed.
#
# Usage:
#   push_branch.sh
#   push_branch.sh [--branch <name>] [--remote <remote>] [--force]
#
# Examples:
#   push_branch.sh
#   push_branch.sh --branch feature/metadrive-simulation-309
#   push_branch.sh --force

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"

_show_help() {
  cat << 'EOF'
Usage: push_branch.sh [options]

Pushes the current (or specified) branch to the remote, setting upstream tracking
if this is the first push.

Options:
  --branch <name>  Branch to push. Defaults to the current branch.
  --remote <name>  Remote to push to. Defaults to "origin".
  --force          Force-push (use with caution).
  --dry-run        Show what would be pushed without actually pushing.
  --help, -h       Show this help.

Examples:
  push_branch.sh
  push_branch.sh --branch feature/my-feature-309
  push_branch.sh --remote origin --force
EOF
}

branch=""
remote="origin"
force=false
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)   branch="$2"; shift 2 ;;
    --remote)   remote="$2"; shift 2 ;;
    --force)    force=true; shift ;;
    --dry-run)  dry_run=true; shift ;;
    --help|-h)  _show_help; exit 0 ;;
    *)          echo "Error: unknown flag '$1'" >&2; _show_help; exit 1 ;;
  esac
done

cd "${REPO_ROOT}"

# Resolve branch
if [[ -z "${branch}" ]]; then
  branch="$(git rev-parse --abbrev-ref HEAD)"
fi

if [[ "${branch}" == "HEAD" ]]; then
  echo "Error: detached HEAD state — specify --branch explicitly." >&2
  exit 1
fi

# Check if upstream is already set
has_upstream=false
if git config "branch.${branch}.remote" &>/dev/null; then
  has_upstream=true
fi

push_args=("${remote}" "${branch}")
if ! "${has_upstream}"; then
  push_args=("--set-upstream" "${remote}" "${branch}")
fi
if "${force}"; then
  push_args=("--force-with-lease" "${push_args[@]}")
fi

echo "Branch: ${branch}  →  ${remote}"
if "${dry_run}"; then
  echo "[dry-run] git push ${push_args[*]}"
else
  git push "${push_args[@]}"
  echo "Pushed."
fi
