#!/usr/bin/env bash
# Shared environment for GitLab shell tools.
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

set -euo pipefail

_GITLAB_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${_GITLAB_ENV_DIR}/../../.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: .env not found at ${ENV_FILE}" >&2
  exit 1
fi

set -a
# shellcheck source=/dev/null
source "${ENV_FILE}"
set +a

if [[ -z "${GL_TOKEN:-}" ]]; then
  echo "Error: GL_TOKEN not set in .env" >&2
  exit 1
fi

if [[ -z "${GL_URL:-}" ]]; then
  echo "Error: GL_URL not set in .env" >&2
  exit 1
fi
if [[ -z "${GL_NAMESPACE:-}" ]]; then
  echo "Error: GL_NAMESPACE not set in .env" >&2
  exit 1
fi

GITLAB_URL="${GL_URL}"
GITLAB_NAMESPACE="${GL_NAMESPACE}"

# Hostname extracted from GITLAB_URL for regex matching (strips scheme)
_GITLAB_HOST="${GITLAB_URL#https://}"
_GITLAB_HOST="${_GITLAB_HOST#http://}"

# resolve_ref <ref> — prints "mr|issue <project_path> <iid>"
# Accepts full URLs or short refs: project#MR!id  project#id
resolve_ref() {
  local ref="$1"

  # Full URL: https://<host>/<path>/-/(merge_requests|issues|work_items)/<id>
  if [[ "${ref}" =~ ^https?://${_GITLAB_HOST}/(.+)/-/(merge_requests|issues|work_items)/([0-9]+) ]]; then
    local path="${BASH_REMATCH[1]}" kind="${BASH_REMATCH[2]}" iid="${BASH_REMATCH[3]}"
    if [[ "${kind}" == "merge_requests" ]]; then
      echo "mr ${path} ${iid}"
    else
      echo "issue ${path} ${iid}"
    fi
    return 0
  fi

  # Short MR: project#MR!id
  if [[ "${ref}" =~ ^([^#]+)#MR!([0-9]+)$ ]]; then
    echo "mr ${GITLAB_NAMESPACE}/${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    return 0
  fi

  # Short issue: project#id
  if [[ "${ref}" =~ ^([^#]+)#([0-9]+)$ ]]; then
    echo "issue ${GITLAB_NAMESPACE}/${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
    return 0
  fi

  echo "Error: cannot parse ref '${ref}'" >&2
  echo "  Accepted formats:" >&2
  echo "    Full URL:    ${GITLAB_URL}/<path>/-/merge_requests/<id>" >&2
  echo "    Short MR:    projectX#MR!177" >&2
  echo "    Short issue: projectX#300" >&2
  return 1
}

# api_get <endpoint> — authenticated GET, returns JSON to stdout
api_get() {
  curl -sf \
    --header "PRIVATE-TOKEN: ${GL_TOKEN}" \
    "${GITLAB_URL}/api/v4${1}"
}

# url_encode <string> — percent-encodes a string (uses python3, always available)
url_encode() {
  python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$1"
}
