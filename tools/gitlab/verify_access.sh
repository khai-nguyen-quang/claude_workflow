#!/usr/bin/env bash
# Verify that GL_TOKEN has valid access to the GitLab instance and the projectX project.
#
# Usage: ./verify_access.sh [--project <short-or-full-path>]
#
# Examples:
#   ./verify_access.sh
#   ./verify_access.sh --project projectX
#   ./verify_access.sh --project company-base/.../vision-camera/projectX

set -euo pipefail

# shellcheck source=tools/gitlab/_env.sh
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

_show_help() {
  cat << 'EOF'
Usage: verify_access.sh [--project <name>] [--help]

Verifies GL_TOKEN can authenticate and read the target project.

Options:
  --project <name>   Short project name (e.g. projectX) or full namespace path.
                     Defaults to "projectX".
  --help, -h         Show this help.

Examples:
  ./verify_access.sh
  ./verify_access.sh --project projectB
EOF
}

project_name="projectX"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) project_name="$2"; shift 2 ;;
    --help|-h) _show_help; exit 0 ;;
    *) echo "Error: unknown flag '$1'" >&2; _show_help; exit 1 ;;
  esac
done

# Resolve project path: if it contains a slash treat as full path, else prepend namespace
if [[ "${project_name}" == */* ]]; then
  project_path="${project_name}"
else
  project_path="${GITLAB_NAMESPACE}/${project_name}"
fi

encoded="$(url_encode "${project_path}")"

echo "=== GitLab Access Verification ==="
echo "Instance: ${GITLAB_URL}"
echo "Project:  ${project_path}"
echo ""

# 1. Verify token (current user)
echo "[1/2] Checking token identity..."
user_json="$(api_get "/user")"
username="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['username'])" <<< "${user_json}")"
name="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['name'])" <<< "${user_json}")"
echo "      Authenticated as: ${name} (@${username})"

# 2. Verify project access
echo "[2/2] Checking project access..."
project_json="$(api_get "/projects/${encoded}")"
proj_name="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['name_with_namespace'])" <<< "${project_json}")"
visibility="$(python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d['visibility'])" <<< "${project_json}")"
echo "      Project: ${proj_name}"
echo "      Visibility: ${visibility}"

echo ""
echo "Access OK."
