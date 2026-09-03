#!/usr/bin/env bash
# TeammateIdle hook — THE LOOP (template/epic_workflow.md §6).
#
# Exit 2 sends feedback and keeps the teammate working. Without this the pipeline
# halts quietly the first time an agent decides it is done; with it, an agent that
# goes idle while its lane still has claimable work is pushed back to the queue.
#
# Idling is ALLOWED when the lane has no claimable work — a reviewer waiting on the
# coder is correct behaviour, not a stall.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$(cat)"
LANE="$(printf '%s' "$PAYLOAD" | python3 "${HERE}/_payload.py" lane)"
[[ -z "$LANE" ]] && exit 0

: "${WF_EPIC_QUEUE:?WF_EPIC_QUEUE not set}"
NEXT="$(python3 "${HERE}/../engine/graph.py" --queue "${WF_EPIC_QUEUE}" next 2>/dev/null | awk -v l="$LANE" -F'\t' '$2==l')"

if [[ -n "$NEXT" ]]; then
  echo "Your lane still has claimable work — do not go idle. Claim the next task:"
  printf '%s\n' "$NEXT" | awk -F'\t' '{printf "  %s   (worktree: %s)\n", $1, $3}'
  echo "If a task looks already done, mark it complete rather than leaving it in progress."
  exit 2
fi
exit 0
