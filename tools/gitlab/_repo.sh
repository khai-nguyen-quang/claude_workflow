#!/usr/bin/env bash
# Shared git-repository resolver for workflow shell tools.
#
# Unlike _env.sh, this carries NO .env / GL_TOKEN dependency, so it is safe to
# source from pure-git tools (commit_code.sh, push_branch.sh) that never touch
# the GitLab API.
#
# The workflow layout places the project repo in a SUBDIRECTORY of the workspace
# (e.g. $WORKSPACE_ROOT/openpilot), not at the workspace root itself. Tools must
# therefore resolve the actual repo rather than assuming repo == workspace root.

# resolve_repo_root <workspace_root> [explicit]
# Locate the git repo to operate on. Resolution order:
#   1. <explicit> argument (e.g. from --repo) when non-empty
#   2. $WF_REPO environment variable
#   3. git work-tree toplevel of the current directory (run from inside the repo)
#   4. <workspace_root> itself, if it is a git repo (legacy: repo == workspace)
#   5. the sole depth-1 git-repo child of <workspace_root> (errors if 0 or >1)
# Prints the resolved absolute path on success; returns 1 with guidance otherwise.
resolve_repo_root() {
  local ws="$1" explicit="${2:-}" candidate=""

  if [[ -n "${explicit}" ]]; then
    candidate="${explicit}"
  elif [[ -n "${WF_REPO:-}" ]]; then
    candidate="${WF_REPO}"
  elif candidate="$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null)"; then
    : # candidate set to the CWD's repo toplevel
  elif [[ -d "${ws}/.git" ]]; then
    candidate="${ws}"
  else
    # No explicit hint and not inside a repo: look for a single repo child.
    local found=() d
    for d in "${ws}"/*/; do
      [[ -d "${d}.git" ]] && found+=("${d%/}")
    done
    if [[ ${#found[@]} -eq 1 ]]; then
      candidate="${found[0]}"
    elif [[ ${#found[@]} -eq 0 ]]; then
      echo "Error: no git repository found under '${ws}'." >&2
      echo "  Pass --repo <path>, set WF_REPO, or run from inside the repo." >&2
      return 1
    else
      echo "Error: multiple git repositories under '${ws}':" >&2
      printf '    %s\n' "${found[@]}" >&2
      echo "  Disambiguate with --repo <path> or WF_REPO." >&2
      return 1
    fi
  fi

  if [[ ! -d "${candidate}/.git" ]]; then
    echo "Error: '${candidate}' is not a git repository." >&2
    return 1
  fi
  (cd "${candidate}" && pwd)
}
