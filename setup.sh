#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(pwd)" rev-parse --show-toplevel)"
SRC="$ROOT/.claude"
DST="$HOME/.claude"

# Symlink agents and skills
mkdir -p "$DST/agents" "$DST/skills"
ln -sf "$SRC"/agents/*.md "$DST/agents/"
for d in "$SRC"/skills/*/; do
  ln -sfn "$d" "$DST/skills/$(basename "$d")"
done

# Merge permissions from project settings into user-level settings.
# Arrays (allow, additionalDirectories) are unioned; scalar fields favour user over project.
SRC_SETTINGS="$SRC/settings.json"
DST_SETTINGS="$DST/settings.json"

if [ -f "$SRC_SETTINGS" ]; then
  [ -f "$DST_SETTINGS" ] || echo "{}" > "$DST_SETTINGS"
  tmp=$(mktemp)
  jq -s '
    .[0] as $u | .[1] as $p |
    $u + {
      permissions: (($p.permissions // {}) + ($u.permissions // {}) + {
        allow: ((($u.permissions.allow // []) + ($p.permissions.allow // [])) | unique),
        additionalDirectories: ((($u.permissions.additionalDirectories // []) + ($p.permissions.additionalDirectories // [])) | unique)
      })
    }
  ' "$DST_SETTINGS" "$SRC_SETTINGS" > "$tmp" && mv "$tmp" "$DST_SETTINGS"
  echo "Merged permissions into $DST_SETTINGS"
fi

# Register UserPromptSubmit hooks (idempotent; matched by a substring marker so
# small command drift never produces duplicates).
[ -f "$DST_SETTINGS" ] || echo "{}" > "$DST_SETTINGS"

register_hook() {  # $1 = unique marker substring, $2 = command
  local marker="$1" cmd="$2" tmp
  tmp=$(mktemp)
  jq --arg marker "$marker" --arg cmd "$cmd" '
    .hooks //= {} |
    .hooks.UserPromptSubmit //= [] |
    if ([.hooks.UserPromptSubmit[].hooks[]?.command // empty | select(contains($marker))] | length) > 0
    then .
    else .hooks.UserPromptSubmit += [{hooks: [{type: "command", command: $cmd}]}]
    end
  ' "$DST_SETTINGS" > "$tmp" && mv "$tmp" "$DST_SETTINGS"
}

# Sticky /wf mode: routes bare prompts through the wf skill while active.
register_hook "wf_mode_hook.sh" "bash $ROOT/tools/wf_mode_hook.sh"

# Active workflow state injector: surfaces the latest *_state.md every turn.
STATE_CMD="$(cat <<'EOF'
state=$(find __TMP__ -name "*_state.md" -type f -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d" " -f2-); if [[ -n "${state}" ]]; then python3 -c "import json,sys; c=open(sys.argv[1]).read(); print(json.dumps({'hookSpecificOutput':{'hookEventName':'UserPromptSubmit','additionalContext':'=== Active workflow state ('+sys.argv[1]+') ===\\n'+c}}))" "${state}"; fi
EOF
)"
STATE_CMD="${STATE_CMD//__TMP__/$ROOT/.tmp}"
register_hook "_state.md" "$STATE_CMD"

echo "Registered UserPromptSubmit hooks in $DST_SETTINGS"
