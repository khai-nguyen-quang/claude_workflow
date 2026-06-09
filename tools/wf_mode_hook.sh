#!/usr/bin/env bash
# UserPromptSubmit hook for sticky /wf mode.
#
# When the flag file exists (created by `/wf start`, removed by `/wf stop`),
# every bare prompt is routed through the wf skill. Prompts that are already
# slash commands (start with `/`) pass through untouched, so the user can
# always escape with `/wf stop` or any other slash command.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAG="${SCRIPT_DIR}/../.tmp/.wf_mode_active"

# No flag -> mode inactive, do nothing.
[[ -f "${FLAG}" ]] || exit 0

# Read the prompt from the hook's stdin JSON.
prompt="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("prompt",""))' 2>/dev/null || true)"

# Already a slash command -> let it run normally (covers /wf stop).
case "${prompt}" in
  /*) exit 0 ;;
esac

# Empty prompt -> nothing to route.
[[ -n "${prompt//[[:space:]]/}" ]] || exit 0

python3 - <<'PY'
import json
msg = (
    "Sticky /wf mode is ACTIVE. Treat the user's message this turn as arguments "
    "to the wf skill: invoke the Skill tool with skill=\"wf\" and args set to the "
    "user's verbatim message (e.g. message \"planning projectX#309\" => "
    "/wf planning projectX#309). If the message is not a valid wf phase, the wf "
    "fallback will handle it. The user exits this mode by typing /wf stop."
)
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": msg,
    }
}))
PY
