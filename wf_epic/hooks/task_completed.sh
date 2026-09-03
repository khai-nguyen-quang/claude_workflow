#!/usr/bin/env bash
# TaskCompleted hook — THE GATE (template/epic_workflow.md §6).
#
# Exit 2 rejects the completion and feeds the real failure output back to the agent,
# which must then fix it before the task can close. This replaces every _gate_* in the
# old bash driver. Exit 0 accepts and advances the graph.
#
# Requires: WF_EPIC_QUEUE (path to <epic-slug>_queue.md), WF_EPIC_ROOT (workspace root).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../engine/gates.sh"

PAYLOAD="$(cat)"
TASK="$(printf '%s' "$PAYLOAD" | python3 "${HERE}/_payload.py" task)"
[[ -z "$TASK" ]] && exit 0          # not one of our tasks — never block other work

: "${WF_EPIC_QUEUE:?WF_EPIC_QUEUE not set}"
GRAPH="python3 ${HERE}/../engine/graph.py --queue ${WF_EPIC_QUEUE}"
read -r LANE TICKET ROUND < <(python3 - "$TASK" <<'PY'
import sys; sys.path.insert(0, __import__("os").path.dirname(sys.argv[0]) or ".")
lane, rest = sys.argv[1].split(":", 1)
import re; m = re.fullmatch(r"(.+?)\.r(\d+)", rest)
print(lane, m.group(1) if m else rest, m.group(2) if m else 0)
PY
)
WT="$($GRAPH status --json | python3 -c "
import json,sys
for r in json.load(sys.stdin)['tickets']:
    if r['ticket']=='$TICKET': print(r['worktree']); break")"
TDIR="${WF_EPIC_ROOT:-$PWD}/claude_workflow/.tmp/${TICKET}"

reject() { echo "GATE FAILED — $TASK"; echo; printf '%s\n' "$*"; exit 2; }

case "$LANE" in
  code|fix)
    for g in build test lint asan tsan; do
      out="$(run_gate "$WT" "$g")"; rc=$?
      [[ $rc -eq 1 ]] && reject "gate '$g' failed in $WT:"$'\n'"$out"
      [[ $rc -eq 3 ]] && echo "  $g: $out"
    done
    if [[ "$LANE" == fix ]]; then
      rf="${TDIR}/${TICKET}_review_r${ROUND}.md"
      [[ -f "$rf" ]] || reject "review file missing: $rf"
      open="$(grep -cE '^- \[(blocking|major)\]' "$rf")"
      replied="$(grep -cE '^ +- reply:' "$rf")"
      (( replied < open )) && reject "$((open - replied)) of $open blocking/major findings have no reply in $rf. Reply to every finding: '  - reply: fixed|rejected — <reason>'."
    fi
    $GRAPH advance --ticket "$TICKET" --event "$([[ $LANE == code ]] && echo code-done || echo fix-done)"
    ;;
  review)
    rf="${TDIR}/${TICKET}_review_r${ROUND}.md"
    [[ -f "$rf" ]] || reject "no review report at $rf — a review that did not happen fails the gate."
    verdict="$(grep -oE 'VERDICT: *(PRODUCTION READY|NEEDS WORK)' "$rf" | head -1)"
    [[ -z "$verdict" ]] && reject "$rf carries no verdict. End the report with 'VERDICT: PRODUCTION READY' or 'VERDICT: NEEDS WORK'."
    if [[ "$verdict" == *"PRODUCTION READY"* ]]; then
      $GRAPH advance --ticket "$TICKET" --event review-ok
    else
      n="$(grep -cE '^- \[(blocking|major)\]' "$rf")"
      (( n == 0 )) && reject "verdict is NEEDS WORK but no blocking/major findings are listed in $rf. Classify each finding as '- [blocking]', '- [major]' or '- [minor]'."
      $GRAPH advance --ticket "$TICKET" --event review-findings --findings "$n"
    fi
    ;;
  *) exit 0 ;;
esac

$GRAPH status | tail -5
exit 0
