#!/usr/bin/env bash
set -euo pipefail

SRC="$(git -C "$(pwd)" rev-parse --show-toplevel)/.claude"
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
