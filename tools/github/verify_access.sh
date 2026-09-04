#!/usr/bin/env bash
# Verify that the configured GitHub token authenticates and can read a repository.
#
# Usage: ./verify_access.sh [--repo <owner/repo>]
#
# Examples:
#   ./verify_access.sh
#   ./verify_access.sh --repo khai-nguyen-quang/dash-cam

set -euo pipefail

# shellcheck source=tools/github/_env.sh
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

_show_help() {
  cat << 'HELP'
Usage: verify_access.sh [--repo <owner/repo>] [--help]

Verifies the configured token can authenticate and read the target repository.
Reports which .env variable supplied it.

Options:
  --repo <owner/repo>  Repository to check. Without it, only authentication and
                       the list of reachable repositories are shown.
  --help, -h           Show this help.
HELP
}

repo=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)    repo="$2"; shift 2 ;;
    --help|-h) _show_help; exit 0 ;;
    *)         echo "Error: unknown argument '$1'" >&2; _show_help; exit 1 ;;
  esac
done

echo "GitHub API: ${GITHUB_API}"

user_json="$(api_get "/user")" || { echo "Error: authentication failed — check ${GH_TOKEN_SOURCE}." >&2; exit 1; }
login="$(echo "${user_json}" | python3 -c "import json,sys; print(json.load(sys.stdin)['login'])")"
echo "Authenticated as: ${login}   (token from ${GH_TOKEN_SOURCE})"

if [[ -z "${repo}" ]]; then
  echo ""
  echo "Reachable repositories:"
  api_get "/user/repos?per_page=100&sort=updated" | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    print(f\"  {r['full_name']:50} {'private' if r['private'] else 'public':8} issues={r['has_issues']}\")
"
  echo ""
  echo "Pass --repo <owner/repo> to check a specific repository."
  exit 0
fi

echo ""
echo "Checking ${repo}..."
if ! repo_json="$(api_get "/repos/${repo}")"; then
  echo "Error: cannot read '${repo}'." >&2
  echo "" >&2
  echo "  If git works for this repo over SSH but this check fails, the token's" >&2
  echo "  repository access does not include it. Fine-grained personal access" >&2
  echo "  tokens list their repositories explicitly:" >&2
  echo "    Settings > Developer settings > Personal access tokens >" >&2
  echo "      Fine-grained tokens > <token> > Repository access" >&2
  echo "  The workflow needs: Issues RW, Contents RW, Pull requests RW, Metadata R." >&2
  exit 1
fi

echo "${repo_json}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(f\"  Full name:      {d['full_name']}\")
print(f\"  Visibility:     {'private' if d['private'] else 'public'}\")
print(f\"  Default branch: {d['default_branch']}\")
print(f\"  Issues enabled: {d['has_issues']}\")
perms = d.get('permissions') or {}
print(f\"  Permissions:    admin={perms.get('admin')} push={perms.get('push')} pull={perms.get('pull')}\")
if not d['has_issues']:
    print('  WARNING: issues are disabled on this repository — /wf and /wf-epic need them.')
"
echo ""
echo "Access OK."
