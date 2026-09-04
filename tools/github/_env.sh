#!/usr/bin/env bash
# Shared environment for GitHub shell tools.
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"
#
# Mirrors tools/gitlab/_env.sh. Only GH_TOKEN is required -- there is no
# instance URL or namespace to configure, because a GitHub ref always carries
# its own owner/repo.

set -euo pipefail

_GITHUB_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${_GITHUB_ENV_DIR}/../../.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: .env not found at ${ENV_FILE}" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "Error: GH_TOKEN not set in .env" >&2
  exit 1
fi

GITHUB_API="https://api.github.com"
GITHUB_WEB="https://github.com"

# resolve_ref <ref> — prints "mr|issue <owner> <repo> <number>"
# Accepts full URLs or short refs: owner/repo#PR!45  owner/repo#12
resolve_ref() {
  local ref="$1"

  if [[ "${ref}" =~ ^https?://[^/]+/([^/]+)/([^/]+)/(issues|pull)/([0-9]+) ]]; then
    local owner="${BASH_REMATCH[1]}" repo="${BASH_REMATCH[2]}"
    local kind="${BASH_REMATCH[3]}" number="${BASH_REMATCH[4]}"
    if [[ "${kind}" == "pull" ]]; then
      echo "mr ${owner} ${repo} ${number}"
    else
      echo "issue ${owner} ${repo} ${number}"
    fi
    return 0
  fi

  if [[ "${ref}" =~ ^([^/#]+)/([^/#]+)#PR!([0-9]+)$ ]]; then
    echo "mr ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    return 0
  fi

  if [[ "${ref}" =~ ^([^/#]+)/([^/#]+)#([0-9]+)$ ]]; then
    echo "issue ${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    return 0
  fi

  echo "Error: cannot parse GitHub ref '${ref}'" >&2
  echo "  Accepted formats:" >&2
  echo "    Full URL:    ${GITHUB_WEB}/<owner>/<repo>/issues/<n>" >&2
  echo "    Short PR:    <owner>/<repo>#PR!45" >&2
  echo "    Short issue: <owner>/<repo>#12" >&2
  return 1
}

# api_get <endpoint> — authenticated GET, returns JSON to stdout
api_get() {
  curl -sf \
    --header "Authorization: Bearer ${GH_TOKEN}" \
    --header "Accept: application/vnd.github+json" \
    --header "X-GitHub-Api-Version: 2022-11-28" \
    "${GITHUB_API}$1"
}

# url_encode <string> — percent-encodes a string
url_encode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}
