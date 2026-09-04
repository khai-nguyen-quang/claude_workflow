#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(pwd)" rev-parse --show-toplevel)"
WORKSPACE_ROOT="$(cd "$ROOT/.." && pwd)"
SRC="$ROOT/.claude"
DST="$HOME/.claude"

WITH_EPIC=true
WITH_PROJECTS=true
for arg in "$@"; do
  case "$arg" in
    --no-epic) WITH_EPIC=false ;;
    --no-projects) WITH_PROJECTS=false ;;
    --help|-h)
      cat << 'HELP'
Usage: ./setup.sh [--no-epic]

Installs the claude_workflow skills, agents, permissions and hooks into ~/.claude.

Options:
  --no-epic       Skip /wf-epic. Its settings enable agent teams and tmux teammate
                  mode GLOBALLY for every Claude session on this machine, so skip
                  it if you only want /wf.
  --no-projects   Skip registering sibling repositories.
HELP
      exit 0 ;;
  esac
done

# jq drives every settings merge below; without it this script would corrupt
# settings.json rather than fail.
for cmd in jq python3 git curl; do
  command -v "$cmd" > /dev/null || { echo "Error: '$cmd' is required but not installed." >&2; exit 1; }
done

# Symlink agents and skills
mkdir -p "$DST/agents" "$DST/skills"
ln -sf "$SRC"/agents/*.md "$DST/agents/"
for d in "$SRC"/skills/*/; do
  ln -sfn "$d" "$DST/skills/$(basename "$d")"
done

# The epic workflow lives outside .claude/, so it needs wiring of its own --
# without this /wf-epic is simply not a command.
if "$WITH_EPIC"; then
  ln -sfn "$ROOT/wf_epic" "$DST/skills/wf-epic"
  ln -sf "$ROOT"/wf_epic/agents/*.md "$DST/agents/"
  echo "Installed /wf-epic skill and agents"
fi

mkdir -p "$ROOT/.tmp"

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

# Epic engine settings: agent teams, tmux teammates, and the two gate hooks.
# The snippet ships with this machine's paths baked in, so rewrite them to the
# real ROOT rather than trusting them.
EPIC_SNIPPET="$ROOT/wf_epic/settings.snippet.json"
if "$WITH_EPIC" && [ -f "$EPIC_SNIPPET" ]; then
  tmp=$(mktemp)
  jq --arg root "$ROOT" --arg ws "$WORKSPACE_ROOT" '
    del(._comment)
    | .env.WF_EPIC_ROOT = $ws
    | .hooks |= with_entries(
        .value |= map(.hooks |= map(
          .command |= sub("^bash .*/wf_epic/"; "bash " + $root + "/wf_epic/")
        ))
      )
  ' "$EPIC_SNIPPET" > "$tmp"

  merged=$(mktemp)
  jq -s '
    .[0] as $u | .[1] as $e |
    $u
    + {env: (($u.env // {}) + ($e.env // {}))}
    + {teammateMode: ($u.teammateMode // $e.teammateMode)}
    + {subagentPromptCacheTtl: ($u.subagentPromptCacheTtl // $e.subagentPromptCacheTtl)}
    + {hooks: (($u.hooks // {}) + (
         ($e.hooks // {}) | with_entries(
           .key as $k | .value |= (
             # Keep any hook the user already registered for this event, and add
             # ours only when no entry mentions the same script.
             ($u.hooks[$k] // []) as $existing
             | if ([$existing[].hooks[]?.command // empty
                    | select(test("wf_epic/hooks"))] | length) > 0
               then $existing else $existing + . end
           )
         )
       ))}
  ' "$DST_SETTINGS" "$tmp" > "$merged" && mv "$merged" "$DST_SETTINGS"
  rm -f "$tmp"
  echo "Merged epic engine settings into $DST_SETTINGS"
  echo "  NOTE: agent teams and tmux teammate mode are now on for EVERY Claude"
  echo "        session on this machine. Re-run with --no-epic to skip that."
fi

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

# Register every sibling repository: one project context file, one worktree conf,
# and the workflow import in the project's own CLAUDE.md.
#
# This only ever CREATES missing files. An existing CLAUDE.md is never edited --
# it belongs to that project, and appending to it behind the user's back is not
# this script's call -- so a repo that has one without the import is reported
# instead, with the line to paste.
if "$WITH_PROJECTS"; then
  echo ""
  echo "Registering sibling repositories under $WORKSPACE_ROOT:"
  needs_import=()

  for dir in "$WORKSPACE_ROOT"/*/; do
    dir="${dir%/}"
    name="$(basename "$dir")"

    [ "$dir" = "$ROOT" ] && continue
    case "$name" in *-worktree) continue ;; esac
    git -C "$dir" rev-parse --git-dir > /dev/null 2>&1 || continue

    created=()

    if [ ! -f "$ROOT/projects/${name}_must_read.md" ]; then
      cp "$ROOT/projects/template_must_read.md" "$ROOT/projects/${name}_must_read.md"
      created+=("projects/${name}_must_read.md")
    fi

    if [ ! -f "$ROOT/projects/${name}_worktree.conf" ]; then
      cp "$ROOT/projects/template_worktree.conf" "$ROOT/projects/${name}_worktree.conf"
      created+=("projects/${name}_worktree.conf")
    fi

    if [ ! -f "$dir/CLAUDE.md" ]; then
      cat > "$dir/CLAUDE.md" << CLAUDEEOF
# CLAUDE.md

Guidance for Claude Code when working in this repository.

@../claude_workflow/template/workflow.md

## What this is

<!-- Describe the project: what it does, its main components, how they fit together. -->

## Build and test

<!-- The commands Claude should use. Run \`/wf collect ${name}\` to generate
     projects/${name}_must_read.md from the repository, then add anything
     non-obvious under its "# Technical note" section. -->
CLAUDEEOF
      created+=("${name}/CLAUDE.md")
    elif ! grep -q "claude_workflow/template/workflow.md" "$dir/CLAUDE.md"; then
      needs_import+=("$name")
    fi

    if [ ${#created[@]} -gt 0 ]; then
      printf '  %-28s created %s\n' "$name" "$(IFS=, ; echo "${created[*]}")"
    else
      printf '  %-28s already registered\n' "$name"
    fi
  done

  if [ ${#needs_import[@]} -gt 0 ]; then
    echo ""
    echo "  These repositories have their own CLAUDE.md, which was left untouched."
    echo "  Add this line to each so /wf and /wf-epic load the workflow:"
    echo ""
    echo "      @../claude_workflow/template/workflow.md"
    echo ""
    for n in "${needs_import[@]}"; do echo "    - $n/CLAUDE.md"; done
  fi
fi

echo ""
echo "Installed:"
echo "  skills : $(ls "$DST/skills" | tr '\n' ' ')"
echo "  agents : $(ls "$DST/agents" | wc -l) agent file(s)"
echo "  .env   : $([ -f "$ROOT/.env" ] && echo "present" || echo "MISSING — copy .env_template to .env")"
echo ""
echo "Verify a forge:"
echo "  tools/github/verify_access.sh --repo <owner>/<repo>"
echo "  tools/gitlab/verify_access.sh --project <project>"
