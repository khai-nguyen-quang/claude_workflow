#!/usr/bin/env bash
# Per-ticket git worktree management for the Claude workflow.
#
# Every GitLab ticket (issue or MR) gets its own checkout so several tickets can
# be worked on in parallel Claude sessions without sharing a branch, a build
# directory, or a test-stamp tree:
#
#   $WORKSPACE_ROOT/<project>-worktree/<slug>
#
# <slug> matches the .tmp/ artifact folder name (openpilot-387, openpilot-mr-123),
# so the worktree and the workflow state for a ticket are always named alike.
#
# Usage:
#   worktree.sh ensure <ref> [--branch <name>] [--base <ref>] [--no-carry] [--quiet]
#   worktree.sh path   <ref>
#   worktree.sh list   [<project>]
#   worktree.sh remove <ref> [--force]
#
# Examples:
#   worktree.sh ensure projectX#309        # issue  -> feature/<title-slug>-309 off origin/HEAD
#   worktree.sh ensure projectX#MR!177     # MR     -> the MR's source branch
#   worktree.sh path   projectX#MR!177     # print path only, never creates
#   worktree.sh remove projectX#309

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CLAUDE_WORKFLOW="$(cd "${SCRIPT_DIR}/../.." && pwd)"

_show_help() {
  cat << 'EOF'
Usage: worktree.sh <command> <ref> [options]

Creates and manages one git worktree per GitLab ticket, so multiple tickets can
be worked on in parallel without sharing a branch or a build tree.

Layout:
  $WORKSPACE_ROOT/<project>-worktree/<slug>     <- ticket checkout
  <slug> = <project>-<id> (issue) | <project>-mr-<id> (MR)

Commands:
  ensure <ref>   Create the worktree if missing, reuse it if present. Prints its
                 absolute path on the last line (safe to capture).
  path <ref>     Print the worktree path for <ref>. Never creates anything;
                 exits 3 if it does not exist yet.
  list [project] List workflow worktrees (optionally for one project only).
  remove <ref>   Remove the worktree. Refuses if it holds uncommitted work
                 unless --force is given. The branch itself is never deleted.

Options:
  --branch <name>  Use this branch instead of the one derived from the ticket.
  --base <ref>     Base for a newly created branch. Default: origin/HEAD.
  --no-carry       Skip copying gitignored build assets (see below).
  --quiet          Print only the resolved path.
  --force          remove: discard uncommitted changes.
  --help, -h       Show this help.

Branch selection:
  MR    -> the MR's source branch, fetched from the GitLab API.
  Issue -> an existing local/remote branch ending in -<id> if one exists,
           otherwise a new feature/<title-slug>-<id> off --base.

Carried assets:
  A fresh worktree has no gitignored files, so large downloaded artifacts (ML
  models, vendored sources) would have to be re-fetched per ticket. Paths listed
  in projects/<project>_worktree.conf are hard-linked (cp -al, falling back to a
  copy) from the main checkout: near-zero time and disk, and they are real
  directory entries, so they still resolve inside a Docker bind mount.
EOF
}

_die() { echo "Error: $*" >&2; exit 1; }
_log() { [[ "${quiet}" == true ]] || echo "$*" >&2; }

# --- ref parsing -------------------------------------------------------------
# Sets: kind (issue|mr), project, iid, slug. Short refs are parsed locally so
# that `path` / `list` / `remove` work without GitLab credentials; URL refs fall
# back to resolve_ref, which needs .env.
_parse_ref() {
  local ref="$1"
  if [[ "${ref}" =~ ^([^#/]+)#MR!([0-9]+)$ ]]; then
    kind="mr"; project="${BASH_REMATCH[1]}"; iid="${BASH_REMATCH[2]}"
  elif [[ "${ref}" =~ ^([^#/]+)#([0-9]+)$ ]]; then
    kind="issue"; project="${BASH_REMATCH[1]}"; iid="${BASH_REMATCH[2]}"
  else
    _need_api
    local parts; parts="$(resolve_ref "${ref}")" || exit 1
    kind="$(cut -d' ' -f1 <<< "${parts}")"
    project_path="$(cut -d' ' -f2 <<< "${parts}")"
    iid="$(cut -d' ' -f3 <<< "${parts}")"
    project="${project_path##*/}"
  fi
  [[ "${kind}" == "mr" ]] && slug="${project}-mr-${iid}" || slug="${project}-${iid}"
}

_need_api() {
  [[ -n "${_API_READY:-}" ]] && return 0
  # shellcheck source=claude_workflow/tools/gitlab/_env.sh
  source "${CLAUDE_WORKFLOW}/tools/gitlab/_env.sh"
  _API_READY=1
  project_path="${project_path:-${GITLAB_NAMESPACE}/${project:-}}"
}

_main_repo() {
  local main="${WORKSPACE_ROOT}/${project}"
  git -C "${main}" rev-parse --git-dir &>/dev/null \
    || _die "main checkout not found at '${main}' (expected \$WORKSPACE_ROOT/<project>)."
  echo "${main}"
}

_worktree_path() { echo "${WORKSPACE_ROOT}/${project}-worktree/${slug}"; }

# --- branch resolution -------------------------------------------------------
_default_base() {
  local main="$1" head
  if head="$(git -C "${main}" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
    echo "${head#refs/remotes/}"
  else
    echo "origin/master"
  fi
}

# Prints the branch the worktree should be attached to.
_resolve_branch() {
  local main="$1" existing

  if [[ -n "${branch_opt}" ]]; then echo "${branch_opt}"; return 0; fi

  if [[ "${kind}" == "mr" ]]; then
    _need_api
    local encoded; encoded="$(url_encode "${project_path}")"
    api_get "/projects/${encoded}/merge_requests/${iid}" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["source_branch"])'
    return 0
  fi

  # Issue: reuse an existing branch for this ticket if there is exactly one.
  existing="$(git -C "${main}" for-each-ref --format='%(refname:short)' \
                'refs/heads' "refs/remotes/origin" \
              | sed 's|^origin/||' | grep -E -- "-${iid}\$" | sort -u || true)"
  if [[ "$(wc -l <<< "${existing}")" -eq 1 && -n "${existing}" ]]; then
    echo "${existing}"; return 0
  fi
  if [[ -n "${existing}" ]]; then
    echo "Error: several branches match ticket ${iid}:" >&2
    printf '    %s\n' ${existing} >&2
    echo "  Disambiguate with --branch <name>." >&2
    exit 1
  fi

  # New branch: feature/<title-slug>-<id>, title from the API when reachable.
  local title_slug=""
  if [[ -f "${CLAUDE_WORKFLOW}/.env" ]]; then
    _need_api
    local encoded; encoded="$(url_encode "${project_path}")"
    title_slug="$(api_get "/projects/${encoded}/issues/${iid}" 2>/dev/null \
      | python3 -c '
import json, re, sys
try:
    t = json.load(sys.stdin)["title"]
except Exception:
    sys.exit(0)
s = re.sub(r"[^a-z0-9]+", "-", t.strip().lower()).strip("-")[:40].rstrip("-")
print(s)' || true)"
  fi
  echo "feature/${title_slug:-${project}}-${iid}"
}

# --- worktree creation -------------------------------------------------------
_carry_assets() {
  local main="$1" wt="$2"
  local conf="${CLAUDE_WORKFLOW}/projects/${project}_worktree.conf"
  [[ -f "${conf}" ]] || return 0

  local rel n f src dst
  while IFS= read -r rel; do
    rel="${rel%%#*}"; rel="${rel#"${rel%%[![:space:]]*}"}"; rel="${rel%"${rel##*[![:space:]]}"}"
    [[ -z "${rel}" ]] && continue
    [[ -e "${main}/${rel}" ]] || { _log "  carry: skip '${rel}' (absent in main checkout)"; continue; }

    # Only files git will not provide are carried: ignored ones, plus untracked
    # ones (a vendored checkout is untracked but not ignored, so both lists are
    # needed). Tracked files come from the checkout itself, and hard-linking
    # those would let an in-place edit in one worktree corrupt another.
    n=0
    while IFS= read -r -d '' f; do
      src="${main}/${f}"; dst="${wt}/${f}"
      [[ -e "${dst}" || -L "${src}" ]] && continue
      mkdir -p "$(dirname "${dst}")"
      # Hard-link first: instant and near-zero disk for large read-only blobs.
      cp -al "${src}" "${dst}" 2>/dev/null || cp -a "${src}" "${dst}" || continue
      n=$((n + 1))
    done < <({ git -C "${main}" ls-files -z --others --ignored --exclude-standard -- "${rel}"
               git -C "${main}" ls-files -z --others --exclude-standard -- "${rel}"; })

    if [[ ${n} -gt 0 ]]; then
      _log "  carry: ${rel} (${n} files)"
    else
      _log "  carry: ${rel} — nothing to carry (all tracked, or already present)"
    fi
  done < "${conf}"
}

_cmd_ensure() {
  local main wt branch base
  main="$(_main_repo)"
  wt="$(_worktree_path)"

  if git -C "${main}" worktree list --porcelain | grep -qx "worktree ${wt}"; then
    _log "Worktree exists: ${wt}"
    _log "  branch: $(git -C "${wt}" rev-parse --abbrev-ref HEAD)"
    # Cheap, and it repairs a worktree created before an asset was added to the conf.
    [[ "${carry}" == true ]] && _carry_assets "${main}" "${wt}"
    echo "${wt}"; return 0
  fi
  [[ -e "${wt}" ]] && _die "'${wt}' exists but is not a registered worktree. Move it aside or run 'worktree.sh remove ${ref}'."

  _log "Fetching origin..."
  git -C "${main}" fetch --quiet origin || _log "  warning: fetch failed, continuing with local refs"

  branch="$(_resolve_branch "${main}")"
  base="${base_opt:-$(_default_base "${main}")}"
  mkdir -p "$(dirname "${wt}")"

  local co; co="$(git -C "${main}" worktree list --porcelain | grep -B2 "^branch refs/heads/${branch}\$" | grep '^worktree ' | cut -d' ' -f2- || true)"
  [[ -n "${co}" ]] && _die "branch '${branch}' is already checked out at '${co}'."

  if git -C "${main}" show-ref --quiet "refs/heads/${branch}"; then
    _log "Attaching worktree to existing local branch '${branch}'."
    git -C "${main}" worktree add --quiet "${wt}" "${branch}"
  elif git -C "${main}" show-ref --quiet "refs/remotes/origin/${branch}"; then
    _log "Tracking origin/${branch} in a new worktree."
    git -C "${main}" worktree add --quiet --track -b "${branch}" "${wt}" "origin/${branch}"
  else
    [[ "${kind}" == "mr" ]] && _die "MR source branch '${branch}' not found on origin."
    _log "Creating branch '${branch}' off ${base}."
    git -C "${main}" worktree add --quiet -b "${branch}" "${wt}" "${base}"
  fi

  if [[ -f "${wt}/.gitmodules" ]]; then
    _log "Initialising submodules..."
    git -C "${wt}" submodule update --init --recursive --quiet \
      || _log "  warning: submodule init failed — run it manually before building"
  fi

  [[ "${carry}" == true ]] && _carry_assets "${main}" "${wt}"

  _log ""
  _log "Worktree ready: ${wt}"
  _log "  branch: ${branch}"
  _log "  state:  ${CLAUDE_WORKFLOW}/.tmp/${slug}/"
  echo "${wt}"
}

_cmd_path() {
  local wt; wt="$(_worktree_path)"
  git -C "${WORKSPACE_ROOT}/${project}" worktree list --porcelain 2>/dev/null \
    | grep -qx "worktree ${wt}" || exit 3
  echo "${wt}"
}

_cmd_list() {
  local d
  for d in "${WORKSPACE_ROOT}"/*-worktree/*/; do
    [[ -d "${d}" ]] || continue
    d="${d%/}"
    [[ -n "${1:-}" && "$(basename "$(dirname "${d}")")" != "$1-worktree" ]] && continue
    printf '%-52s %s\n' "${d}" "$(git -C "${d}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  done
}

_cmd_remove() {
  local main wt branch dirty
  main="$(_main_repo)"; wt="$(_worktree_path)"
  [[ -d "${wt}" ]] || _die "no worktree at '${wt}'."
  branch="$(git -C "${wt}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

  # Gate on uncommitted work ourselves: the submodule deinit below is
  # destructive, so it must not run before this check.
  if [[ "${force}" != true ]]; then
    dirty="$(git -C "${wt}" status --porcelain)"
    if [[ -n "${dirty}" ]]; then
      echo "Error: '${wt}' has uncommitted changes:" >&2
      head -20 <<< "${dirty}" >&2
      echo "  Commit or stash them, or re-run with --force to discard." >&2
      exit 1
    fi
  fi

  # `git worktree remove` refuses outright on a worktree containing submodules,
  # so detach them first. --force on the removal is then safe: the dirty check
  # above already ran.
  if [[ -f "${wt}/.gitmodules" ]]; then
    _log "Deinitialising submodules..."
    git -C "${wt}" submodule deinit --all --force --quiet || true
  fi

  git -C "${main}" worktree remove --force "${wt}"
  git -C "${main}" worktree prune
  _log "Removed ${wt} (branch '${branch}' kept)."
}

# --- arg parsing -------------------------------------------------------------
[[ $# -eq 0 ]] && { _show_help; exit 1; }
cmd="$1"; shift
case "${cmd}" in --help|-h|help) _show_help; exit 0 ;; esac

ref=""; branch_opt=""; base_opt=""; carry=true; quiet=false; force=false
kind=""; project=""; project_path=""; iid=""; slug=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)  branch_opt="$2"; shift 2 ;;
    --base)    base_opt="$2"; shift 2 ;;
    --no-carry) carry=false; shift ;;
    --quiet)   quiet=true; shift ;;
    --force)   force=true; shift ;;
    --help|-h) _show_help; exit 0 ;;
    --*)       _die "unknown flag '$1'" ;;
    *)         [[ -z "${ref}" ]] && { ref="$1"; shift; } || _die "unexpected argument '$1'" ;;
  esac
done

case "${cmd}" in
  list) _cmd_list "${ref}" ;;
  ensure|path|remove)
    [[ -z "${ref}" ]] && _die "<ref> is required for '${cmd}'."
    _parse_ref "${ref}"
    "_cmd_${cmd}"
    ;;
  *) _die "unknown command '${cmd}' (expected ensure|path|list|remove)" ;;
esac
