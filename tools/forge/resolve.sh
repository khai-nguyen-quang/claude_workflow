#!/usr/bin/env bash
# Decide which forge a workflow ref belongs to.
#
# Usage:
#   resolve.sh <ref>            # prints: <forge> <absolute-tool-dir>
#   resolve.sh <ref> --forge    # prints: <forge>
#   resolve.sh <ref> --tools    # prints: <absolute-tool-dir>
#   resolve.sh <ref> --epic-tools
#
# This is the ONLY place the github/gitlab decision is made. The /wf and /wf-epic
# skills call it once and export WF_FORGE / WF_TOOLS, so no phase file ever has to
# branch on the forge.
#
# It deliberately does NOT source tools/gitlab/_env.sh: that file exits 1 when
# GL_URL or GL_NAMESPACE is missing, which would make every GitHub ref
# unresolvable on a GitHub-only setup. Absent GL_* simply disables the two rules
# that need it.

set -euo pipefail

_FORGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CW_ROOT="$(cd "${_FORGE_DIR}/.." && pwd)"
# WF_ENV_FILE overrides the location purely so the test suite can exercise the
# GL_*-present and GL_*-absent paths without touching the real .env.
ENV_FILE="${WF_ENV_FILE:-${_CW_ROOT}/.env}"

_show_help() {
  cat << 'HELP'
Usage: resolve.sh <ref> [--forge|--tools|--epic-tools]

Prints which forge a ref belongs to, and the tool directory that serves it.

Ref formats:
  GitHub    owner/repo#12         owner/repo#PR!45
            https://github.com/owner/repo/issues/12
            https://github.com/owner/repo/pull/45
  GitLab    projectX#309          projectX#MR!177        Epic#60
            group/sub/projectX#309
            <GL_URL>/<path>/-/issues/309

A ref with no "/" is always GitLab -- GitHub refs always carry owner/repo.
HELP
}

# Read .env without requiring any particular variable to be present.
GL_URL=""; GL_NAMESPACE=""
if [[ -f "${ENV_FILE}" ]]; then
  while IFS= read -r line; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "${line}" || "${line}" == \#* || "${line}" != *=* ]] && continue
    key="${line%%=*}"; value="${line#*=}"
    key="${key//[[:space:]]/}"
    value="${value%\"}"; value="${value#\"}"; value="${value%\'}"; value="${value#\'}"
    case "${key}" in
      GL_URL)       GL_URL="${value}" ;;
      GL_NAMESPACE) GL_NAMESPACE="${value}" ;;
    esac
  done < "${ENV_FILE}"
fi

ref=""; mode="both"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --forge)      mode="forge"; shift ;;
    --tools)      mode="tools"; shift ;;
    --epic-tools) mode="epic-tools"; shift ;;
    --help|-h)    _show_help; exit 0 ;;
    --*)          echo "Error: unknown flag '$1'" >&2; exit 1 ;;
    *)
      if [[ -z "${ref}" ]]; then ref="$1"; shift
      else echo "Error: unexpected argument '$1'" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -z "${ref}" ]]; then
  echo "Error: ref is required." >&2
  _show_help >&2
  exit 1
fi

forge=""

# Rule 1 -- an explicit github.com URL.
if [[ "${ref}" =~ ^https?://(www\.)?github\.com/ ]]; then
  forge="github"
fi

# Rule 2 -- a URL on the configured GitLab host. Skipped when GL_URL is unset.
if [[ -z "${forge}" && -n "${GL_URL}" ]]; then
  _gl_host="${GL_URL#http://}"; _gl_host="${_gl_host#https://}"; _gl_host="${_gl_host%%/*}"
  if [[ -n "${_gl_host}" && "${ref}" =~ ^https?://"${_gl_host}"/ ]]; then
    forge="gitlab"
  fi
fi

# Any other URL is unresolvable -- do not guess at a third forge.
if [[ -z "${forge}" && "${ref}" =~ ^https?:// ]]; then
  echo "Error: '${ref}' is a URL on a host this workflow does not serve." >&2
  echo "  Known hosts: github.com${GL_URL:+, ${GL_URL}}" >&2
  exit 1
fi

# Rule 3 -- Epic#<n> is a GitLab group epic.
if [[ -z "${forge}" && "${ref}" =~ ^[Ee][Pp][Ii][Cc]#[0-9]+$ ]]; then
  forge="gitlab"
fi

if [[ -z "${forge}" ]]; then
  # Everything before the "#" is the path; a bare project name has no "#" at all.
  path="${ref%%#*}"

  if [[ "${path}" != */* ]]; then
    # Rule 7 -- no slash is always GitLab.
    forge="gitlab"
  elif [[ -n "${GL_NAMESPACE}" && ( "${path}" == "${GL_NAMESPACE}/"* || "${path}" == "${GL_NAMESPACE%%/*}/"* ) ]]; then
    # Rule 4 -- inside the configured GitLab namespace.
    forge="gitlab"
  else
    segments="${path//[!\/]/}"
    if [[ ${#segments} -eq 1 ]]; then
      forge="github"   # Rule 5 -- exactly two segments: owner/repo.
    else
      forge="gitlab"   # Rule 6 -- a deeper path is a GitLab group path.
    fi
  fi
fi

if [[ "${forge}" == "github" ]]; then
  tools="${_CW_ROOT}/tools/github"
  epic_tools="${_CW_ROOT}/wf_epic/tools/github"
else
  tools="${_CW_ROOT}/tools/gitlab"
  epic_tools="${_CW_ROOT}/wf_epic/tools"
fi

case "${mode}" in
  forge)      echo "${forge}" ;;
  tools)      echo "${tools}" ;;
  epic-tools) echo "${epic_tools}" ;;
  *)          echo "${forge} ${tools}" ;;
esac
