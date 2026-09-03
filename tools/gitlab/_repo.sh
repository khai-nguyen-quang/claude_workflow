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
#
# Each ticket additionally gets its own worktree at
# $WORKSPACE_ROOT/<project>-worktree/<slug> (see tools/git/worktree.sh), so a
# tool run for one ticket must never operate on another ticket's checkout. The
# workflow skill exports WF_REPO for exactly this reason -- it is the ticket's
# worktree, and it wins over every filesystem guess below.

# is_git_repo <path>
# True for a normal checkout AND for a linked worktree, whose .git is a FILE
# ("gitdir: ...") rather than a directory. Testing -d "<path>/.git" silently
# rejects every worktree, so always go through this helper.
is_git_repo() {
  local d="$1"
  [[ -n "${d}" && -e "${d}/.git" ]] || return 1
  git -C "${d}" rev-parse --git-dir &>/dev/null
}

# resolve_repo_root <workspace_root> [explicit]
# Locate the git repo to operate on. Resolution order:
#   1. <explicit> argument (e.g. from --repo) when non-empty
#   2. $WF_REPO environment variable (the workflow skill sets this per ticket)
#   3. git work-tree toplevel of the current directory (run from inside the repo
#      or inside one of its worktrees)
#   4. <workspace_root> itself, if it is a git repo (legacy: repo == workspace)
#   5. the sole depth-1 git-repo child of <workspace_root> (errors if 0 or >1)
# Ticket worktrees under <workspace_root>/<project>-worktree/ are deliberately
# NOT auto-discovered in step 5: with several tickets in flight there is no
# single right answer, so they must be selected explicitly (WF_REPO, --repo, or
# by running from inside one).
# Prints the resolved absolute path on success; returns 1 with guidance otherwise.
resolve_repo_root() {
  local ws="$1" explicit="${2:-}" candidate=""

  if [[ -n "${explicit}" ]]; then
    candidate="${explicit}"
  elif [[ -n "${WF_REPO:-}" ]]; then
    candidate="${WF_REPO}"
  elif candidate="$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null)"; then
    : # candidate set to the CWD's repo toplevel (worktree-aware by definition)
  elif is_git_repo "${ws}"; then
    candidate="${ws}"
  else
    # No explicit hint and not inside a repo: look for a single repo child.
    local found=() d
    for d in "${ws}"/*/; do
      is_git_repo "${d%/}" && found+=("${d%/}")
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

  if ! is_git_repo "${candidate}"; then
    echo "Error: '${candidate}' is not a git repository or worktree." >&2
    return 1
  fi
  (cd "${candidate}" && pwd)
}
