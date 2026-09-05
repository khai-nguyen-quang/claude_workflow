---
name: wf
description: >
  Run a single Claude workflow phase for a GitLab or GitHub issue, MR or PR.
  Usage: /wf <phase> <ref>
  Phases: planning, plan-review, coding, test, lint, review, fix_review, collect, debug
  Examples: /wf review projectX#MR!177  |  /wf planning projectX#309  |  /wf fix_review projectX#MR!186  |  /wf collect projectX  |  /wf debug projectX#123  |  /wf debug fcw_not_alert
---

## Parse args

Split the args into `<phase>` (first token) and `<ref>` (everything after).

If args are empty, print this usage and stop:

```
Usage: /wf <phase> <ref>

Phases:
  planning      Phase 1 — brainstorm + design overview/detail [wf-planner agent]
  plan-review   Phase 2 — review design docs for conflicts
  coding        Phase 3 — implement the approved design     [wf-coder agent]
  test          Phase 4 — write unit and integration tests
  lint          Phase 5 — fix lint / code quality violations
  review        Phase 6 — review code or a GitLab MR        [wf-reviewer agent]
  fix_review    Phase 7 — fix review comments               [wf-coder agent]
  collect       Utility — collect project context into a must-read file
  debug         Utility — investigate a bug, produce root cause analysis [wf-debugger agent]

Ref formats:
  GitLab
    projectX#309              issue 309 in projectX
    projectX#MR!177           MR 177 in projectX
    group/sub/projectX#309    full namespace path
  GitHub
    owner/repo#12             issue 12          e.g. khai-nguyen-quang/dash-cam#12
    owner/repo#PR!45          pull request 45
  Either
    <full URL to the issue / MR / PR>
  Other
    projectX                  project name only (for collect phase)
    fcw_not_alert             free-form bug slug (describe the bug in the prompt)

A ref with no "/" is GitLab. A GitHub ref always carries owner/repo.
```

If the first token is **not** a recognized phase, go to **Fallback**.

For the `collect` phase, `<ref>` is a bare project name (no `#`); `<project>` = `<ref>`.

## Prepare context (always, before any phase)

**Step 0 — derive workspace root**
`WORKSPACE_ROOT` is the parent of `claude_workflow/`. Derive it from the workspace-level
`CLAUDE.md` path when that file exists; otherwise take the parent of the `claude_workflow/`
directory this skill lives in. Inject into every agent prompt.

**Step 1 — derive identifiers**
- `<project>`: the part of `<ref>` before `#`, reduced to its **last path segment**, or `<ref>`
  itself if there is no `#`. So `projectX#309` and `khai-nguyen-quang/dash-cam#12` give
  `projectX` and `dash-cam` — never a value containing `/`, which would break both
  `.tmp/<project>-<id>/` and `$WORKSPACE_ROOT/<project>/`.
- `<id>`: number after `#`, `#MR!` or `#PR!`; empty for `collect`

**Step 1.5 — resolve the forge**
Run `$WORKSPACE_ROOT/claude_workflow/tools/forge/resolve.sh <ref>`. It prints
`<forge> <tool-dir>`. Export both:

```bash
WF_FORGE=$(.../tools/forge/resolve.sh "<ref>" --forge)   # github | gitlab
WF_TOOLS=$(.../tools/forge/resolve.sh "<ref>" --tools)   # absolute path to the tool directory
```

Every phase invokes forge tools as `$WF_TOOLS/<tool>` — the two tool directories carry the same
filenames, so no phase ever branches on the forge. Skip this step for `collect`, which touches no
forge.

**Step 2 — load state file** (skip for `collect`)
Read `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md` if it exists → `<state_context>`.

**Step 3 — load project context** (skip for `collect`)
Read `$WORKSPACE_ROOT/<project>/CLAUDE.md` → `<project_context>`.
If missing, warn: "No CLAUDE.md found for `<project>`. Create it with build commands, architecture, and conventions."

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
| `collect` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/collect.md` |
| `debug` | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/debug.md` |
| *(unrecognized)* | `$WORKSPACE_ROOT/claude_workflow/.claude/skills/wf/phases/fallback.md` |

## After each phase

Write or update `$WORKSPACE_ROOT/claude_workflow/.tmp/<project>-<id>/<project>-<id>_state.md`.
The `collect` phase does not use a state file (it is stateless and idempotent).
