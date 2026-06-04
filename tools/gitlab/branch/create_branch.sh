#!/usr/bin/env bash
# Create and checkout a new git branch for a GitLab ticket.
# Branch name convention: feature/<slug>-<ticket-id>
#
# Usage:
#   create_branch.sh <ticket-ref> [--name <branch-name>] [--type <feature|fix|chore>]
#
# Examples:
#   create_branch.sh projectX#309
#   create_branch.sh projectX#309 --name metadrive-simulation
#   create_branch.sh projectX#309 --type fix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"

# shellcheck source=claude_workflow/tools/gitlab/_env.sh
source "${SCRIPT_DIR}/../_env.sh"

_show_help() {
  cat << 'EOF'
Usage: create_branch.sh <ticket-ref> [options]

Creates and checks out a new git branch for a GitLab ticket.
Branch name: <type>/<slug>-<ticket-id>  (e.g. feature/metadrive-simulation-309)

Arguments:
  ticket-ref   Short ref (projectX#309) or full GitLab issue URL.

Options:
  --name <slug>      Custom slug for the branch name (spaces → hyphens).
                     If omitted, the ticket title is fetched and slugified.
  --type <type>      Branch prefix: feature, fix, or chore. Default: feature.
  --no-checkout      Create the branch without switching to it.
  --help, -h         Show this help.

Examples:
  create_branch.sh projectX#309
  create_branch.sh projectX#309 --name metadrive-sim --type feature
  create_branch.sh projectX#309 --no-checkout
EOF
}

ticket_ref=""
branch_slug=""
branch_type="feature"
checkout=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)        branch_slug="$2"; shift 2 ;;
    --type)        branch_type="$2"; shift 2 ;;
    --no-checkout) checkout=false; shift ;;
    --help|-h)     _show_help; exit 0 ;;
    --*)           echo "Error: unknown flag '$1'" >&2; _show_help; exit 1 ;;
    *)
      if [[ -z "${ticket_ref}" ]]; then ticket_ref="$1"; shift
      else echo "Error: unexpected argument '$1'" >&2; exit 1
      fi
      ;;
  esac
done

if [[ -z "${ticket_ref}" ]]; then
  echo "Error: ticket-ref is required." >&2
  _show_help; exit 1
fi

case "${branch_type}" in
  feature|fix|chore) ;;
  *) echo "Error: --type must be feature, fix, or chore (got '${branch_type}')" >&2; exit 1 ;;
esac

# Resolve the ref to get project + iid
ref_parts="$(resolve_ref "${ticket_ref}")"
kind="$(echo "${ref_parts}" | cut -d' ' -f1)"
project_path="$(echo "${ref_parts}" | cut -d' ' -f2)"
iid="$(echo "${ref_parts}" | cut -d' ' -f3)"

if [[ "${kind}" != "issue" ]]; then
  echo "Error: '${ticket_ref}' is a merge request, not an issue." >&2
  exit 1
fi

# Fetch ticket title if no slug given
if [[ -z "${branch_slug}" ]]; then
  encoded="$(url_encode "${project_path}")"
  title="$(api_get "/projects/${encoded}/issues/${iid}" | \
    python3 -c "import json,sys; print(json.load(sys.stdin)['title'])")"
  # Slugify: lowercase, replace non-alphanum with hyphens, collapse and trim
  branch_slug="$(echo "${title}" | python3 -c "
import sys, re
s = sys.stdin.read().strip().lower()
s = re.sub(r'[^a-z0-9]+', '-', s)
s = s.strip('-')[:40].rstrip('-')
print(s)
")"
fi

branch_name="${branch_type}/${branch_slug}-${iid}"

cd "${REPO_ROOT}"

if git show-ref --quiet "refs/heads/${branch_name}"; then
  echo "Error: branch '${branch_name}' already exists." >&2
  exit 1
fi

echo "Creating branch: ${branch_name}"
git branch "${branch_name}"

if "${checkout}"; then
  git checkout "${branch_name}"
  echo "Switched to branch '${branch_name}'."
else
  echo "Branch created (not checked out)."
fi
