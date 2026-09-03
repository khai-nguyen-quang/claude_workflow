#!/usr/bin/env bash
# Commit staged (or specified) files and push to the current branch's remote.
#
# Usage:
#   commit_code.sh "commit message"
#   commit_code.sh "commit message" file1.cc file2.py ...
#   commit_code.sh --all "commit message"
#
# Without explicit files, commits only already-staged changes.
# With --all, runs `git add -A` first (stages all tracked/untracked changes).
# With explicit files, stages those files before committing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=claude_workflow/tools/gitlab/_repo.sh
source "${SCRIPT_DIR}/_repo.sh"

_show_help() {
  cat << 'EOF'
Usage: commit_code.sh [--all] <message> [file ...]
       commit_code.sh --help

Commits and pushes code to the current branch's remote.

Options:
  --all          Stage all changes (git add -A) before committing.
  --repo <path>  Repository to operate on. Defaults to $WF_REPO, else the repo of
                 the current directory, else the sole repo under the workspace.
  --dry-run      Show what would happen without actually committing or pushing.
  --no-push      Commit but do not push.
  --help, -h     Show this help.

Arguments:
  message      Commit message (required).
  file ...     Optional list of files to stage before committing.
               If omitted (and --all not set), commits currently staged changes.

Examples:
  commit_code.sh "fix: correct camera init order"
  commit_code.sh --all "feat: add streamerd timeout handling"
  commit_code.sh "refactor: split encoder logic" system/encoderd/encoder.cc
EOF
}

add_all=false
dry_run=false
no_push=false
repo_opt=""
message=""
files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)      add_all=true; shift ;;
    --repo)     repo_opt="$2"; shift 2 ;;
    --dry-run)  dry_run=true; shift ;;
    --no-push)  no_push=true; shift ;;
    --help|-h)  _show_help; exit 0 ;;
    --*)        echo "Error: unknown flag '$1'" >&2; _show_help; exit 1 ;;
    *)
      if [[ -z "${message}" ]]; then
        message="$1"; shift
      else
        files+=("$1"); shift
      fi
      ;;
  esac
done

if [[ -z "${message}" ]]; then
  echo "Error: commit message is required." >&2
  _show_help
  exit 1
fi

# Enforce the no-attribution rule: a commit message must never carry a
# `Co-Authored-By:` trailer crediting Claude/Anthropic (or any Anthropic
# noreply address). Strip such lines rather than failing, so the rule holds
# even if a caller passes one in. See claude_workflow/instructions/gitlab.md.
_attr_re='^[[:space:]]*Co-Authored-By:.*(Claude|Anthropic|noreply@anthropic\.com)'
if printf '%s\n' "${message}" | grep -qiE "${_attr_re}"; then
  echo "Warning: stripping Claude/Anthropic 'Co-Authored-By:' trailer from commit message." >&2
  # Command substitution strips trailing newlines, so the blank separator left
  # before a trailing trailer is removed automatically.
  message="$(printf '%s\n' "${message}" | grep -viE "${_attr_re}" || true)"
fi

if [[ -z "${message//[[:space:]]/}" ]]; then
  echo "Error: commit message is empty after stripping attribution trailers." >&2
  exit 1
fi

REPO_ROOT="$(resolve_repo_root "${WORKSPACE_ROOT}" "${repo_opt}")"
cd "${REPO_ROOT}"

branch="$(git rev-parse --abbrev-ref HEAD)"
remote="$(git config "branch.${branch}.remote" 2>/dev/null || echo "origin")"

echo "Branch: ${branch}  →  remote: ${remote}"
echo ""

# Stage files
if "${add_all}"; then
  echo "Staging all changes (git add -A)..."
  "${dry_run}" || git add -A
elif [[ ${#files[@]} -gt 0 ]]; then
  echo "Staging: ${files[*]}"
  "${dry_run}" || git add -- "${files[@]}"
fi

# Show what will be committed
echo "Changes to commit:"
git diff --cached --stat || true
echo ""

staged_count="$(git diff --cached --name-only | wc -l | tr -d ' ')"
if [[ "${staged_count}" -eq 0 ]]; then
  echo "Nothing staged to commit."
  exit 0
fi

# Commit
echo "Committing: \"${message}\""
if "${dry_run}"; then
  echo "[dry-run] git commit -m \"${message}\""
else
  git commit -m "${message}"
fi

# Push
if "${no_push}"; then
  echo "Skipping push (--no-push)."
  exit 0
fi

echo "Pushing to ${remote}/${branch}..."
if "${dry_run}"; then
  echo "[dry-run] git push ${remote} ${branch}"
else
  git push "${remote}" "${branch}"
fi

echo ""
echo "Done."
