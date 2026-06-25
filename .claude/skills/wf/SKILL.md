---
name: wf
description: >
  Run a single Claude workflow phase for a GitLab issue or MR.
  Usage: /wf <phase> <ref>
  Phases: planning, plan-review, coding, test, lint, review, fix_review, create_mr, collect, debug
  Examples: /wf review projectX#MR!177  |  /wf planning projectX#309  |  /wf create_mr projectX#309  |  /wf fix_review projectX#MR!186  |  /wf collect projectX  |  /wf debug projectX#123  |  /wf debug fcw_not_alert
---

## Parse args

Split the args into `<phase>` (first token) and `<ref>` (everything after).

If args are empty, print this usage and stop:

```
Usage: /wf <phase> <ref>

Phases:
  planning      Phase 1 — brainstorm + design               [superpowers:brainstorming → wf-planner]
  plan-review   Phase 2 — review design docs for conflicts
  coding        Phase 3 — implement the approved design     [wf-coder agent]
  test          Phase 4 — write unit and integration tests
  lint          Phase 5 — fix lint / code quality violations
  review        Phase 6 — review code or a GitLab MR        [wf-reviewer agent]
  fix_review    Phase 7 — fix review comments               [wf-coder agent]
  create_mr     Phase 8 — create the MR for a completed issue
  collect       Utility — collect project context into a must-read file
  debug         Utility — investigate a bug, produce root cause analysis [wf-debugger agent]

Ref formats:
  projectX#309        GitLab issue 309 in projectX
  projectX#MR!177     GitLab MR 177 in projectX
  projectX            Project name only (for collect phase)
  projectX#123        GitLab issue for debug phase
  fcw_not_alert       Free-form bug slug (describe bug in the prompt message)
```

If the first token is `start` or `stop`, handle **Sticky mode** below and stop.

If the first token is **not** a recognized phase, go to **Fallback**.

For the `collect` phase, `<ref>` is a bare project name (no `#`); `<project>` = `<ref>`.

## Sticky mode (`start` / `stop`)

A flag file `$WORKSPACE_ROOT/claude_workflow/.tmp/.wf_mode_active` toggles sticky mode.
While it exists, a `UserPromptSubmit` hook (`tools/wf_mode_hook.sh`) re-injects, on every
turn, an instruction to route the user's bare message through this skill — so the user can
drop the `/wf` prefix and just type `planning projectX#309`, `review projectX#MR!177`, etc.

- `/wf start` — create the flag file (`mkdir -p` the `.tmp/` dir, then `touch` it) and reply:
  "Sticky `/wf` mode **on**. Bare messages now run as workflow commands (e.g. `planning projectX#309`). Slash commands still work normally; type `/wf stop` to exit."
- `/wf stop` — delete the flag file and reply: "Sticky `/wf` mode **off**."

When the hook routes a bare message here, parse and dispatch it exactly as a normal `/wf` invocation.

## Prepare context (always, before any phase)

**Step 0 — derive workspace root**
`WORKSPACE_ROOT` is the parent of `claude_workflow/`. Derive it from the workspace-level `CLAUDE.md` path. Inject into every agent prompt.

**Step 1 — derive identifiers**
- `<project>`: part of `<ref>` before `#`, or `<ref>` itself if no `#`
- `<id>`: number after `#` or `#MR!`; empty for `collect`

**Step 2 — load state file** (skip for `collect`)
Read `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md` if it exists → `<state_context>`.

**Step 3 — forward must_read context** (skip for `collect`)
Read `$WORKSPACE_ROOT/claude_workflow/projects/<project>_must_read.md` **once** — the skill is the
**single reader** of this file. Agents and instruction files never read it themselves; they consume
only what the skill forwards. Extract two blocks:

1. `<technical_note>` — from its `# Technical note` section, the subsection for this phase, matched
   by heading **text** at any level (`##` or `###`), capturing from that heading through to the next
   heading of equal-or-higher level:

   | Phase | Subsection forwarded |
   |-------|----------------------|
   | `planning`, `plan-review`, `review` | `Features` |
   | `coding`, `test`, `lint`, `fix_review` | `Coding and Testing` |
   | `debug` | the entire `# Technical note` |

2. `<setup_commands>` — the **entire `# Setup instructions` section** (compile / unit-test /
   integration-test / lint / run commands), reproduced verbatim. Forwarded for **every** phase.

If the file is missing, set both blocks to `(not available)` and warn: "No `<project>` must_read
found. Run `/wf collect <project>` first." If only the matching Technical note subsection is
missing, set `<technical_note>` = `(not available)` and warn likewise.

Agent phases inject both `<technical_note>` and `<setup_commands>` into the agent prompt (see each
phase file). The inline phases (`plan-review`, `test`, `lint`) and the `planning` brainstorming
step run in the main session, which now holds both blocks — apply them. `CLAUDE.md` (project
architecture) is still read by each agent via its **Required reading**; the skill is the **sole
source for all `_must_read.md`-derived content** (both the Technical note and the setup commands).

## Phase dispatch

For each phase, read the corresponding file and follow it exactly:

| Phase | File |
|-------|------|
| `planning` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/planning.md` |
| `plan-review` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/plan-review.md` |
| `coding` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/coding.md` |
| `test` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/test.md` |
| `lint` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/lint.md` |
| `review` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/review.md` |
| `fix_review` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/fix_review.md` |
| `create_mr` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/create_mr.md` |
| `collect` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/collect.md` |
| `debug` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/debug.md` |
| *(unrecognized)* | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/fallback.md` |

## Guardrails (all phases)

**Never push code without explicit confirmation.** Before any `git push` /
`push_branch.sh`, stop and show the user the branch, the remote, and the commits to be
pushed, then ask "Push this branch?" and wait for an explicit yes. This applies even when
a phase (e.g. `create_mr`) needs the branch pushed to proceed — confirm first, never push
silently.

**Commit messages carry no Claude/Anthropic attribution.** When creating a commit, never
add a `Co-Authored-By:` trailer (e.g. `Co-Authored-By: Claude Opus 4.8
<noreply@anthropic.com>`) or any similar attribution line. The message is the change
description only.

## After each phase

Write or update `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md`.
The `collect` phase does not use a state file (it is stateless and idempotent).
