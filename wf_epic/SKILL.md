---
name: wf-epic
description: >
  Run one phase of the epic workflow for a group-level GitLab epic or a GitHub parent issue.
  Usage: /wf-epic <phase> <epic-ref>
  Phases: research, design, split, implementation, status
  Examples: /wf-epic research Epic#60 | /wf-epic implementation Epic#116 | /wf-epic research khai-nguyen-quang/dash-cam#1
---

## Parse args

`<phase>` is the first token, `<ref>` the rest. With no args, print this and stop:

```
Usage: /wf-epic <phase> <epic-ref>

  research        Phase 1 — 3 lenses + consolidator          -> _strategy.md
  design          Phase 2 — draft/review/fix loop, <=3 rounds -> _design.md
  split           Phase 3 — reconcile existing + new tickets  (human confirms)
  implementation  Phase 4 — AGENT TEAM, streams every ticket  -> MRs
  status          Show the implementation queue

Epic refs:
  GitLab  Epic#60             -> ${GL_URL}/groups/${GL_NAMESPACE}/-/epics/60   (GROUP-level)
  GitHub  owner/repo#1        -> https://github.com/owner/repo/issues/1
          The epic IS an ordinary issue; its children are native sub-issues.

For a single ticket, MR or PR use /wf instead.
```

## Prepare context (before any phase)

**Step 0 — paths.** `WORKSPACE_ROOT` is the parent of `claude_workflow/`.
`WF_EPIC` = `$WORKSPACE_ROOT/claude_workflow/wf_epic`.

**Step 1 — identifiers.** `<ref>` must be one of:

- **GitLab** `Epic#<id>` (case-insensitive) — a group-level epic.
- **GitHub** `<owner>/<repo>#<n>` — a parent issue.

If it looks like `<project>#MR!<id>` or `<owner>/<repo>#PR!<n>`, stop and point the user at `/wf`
— this skill is for epics only.

Resolve the forge and the epic tool directory once, with
`$WORKSPACE_ROOT/claude_workflow/tools/forge/resolve.sh`:

```bash
WF_FORGE=$(.../tools/forge/resolve.sh "<ref>" --forge)         # github | gitlab
WF_TOOLS_EPIC=$(.../tools/forge/resolve.sh "<ref>" --epic-tools)
```

Every phase invokes `$WF_TOOLS_EPIC/<tool>` — both directories carry the same filenames
(`fetch_epic.py`, `create_issue.py`, `update_epic.py`), so no phase branches on the forge.

- `<epic-id>` = the number after `Epic#` (GitLab) or after `#` (GitHub)
- `<epic-slug>` = `epic-<epic-id>` on GitLab, `<repo>-epic-<epic-id>` on GitHub, so the two forges
  cannot collide in `.tmp/`
- `<epic-dir>` = `$WORKSPACE_ROOT/claude_workflow/.tmp/<epic-slug>/`

**Step 2 — no worktree.** Phases 1–3 produce documents and tickets, never code: they read the main
checkouts and commit nothing. Worktrees are per **child ticket** and are created by phase 4's seed
script. Never `git checkout` or commit in a main checkout.

**Step 3 — state.** Read `<epic-dir>/<epic-slug>_state.md` if it exists.

**Step 4 — project scope.** An epic may span projects: a GitLab epic is group-level, and GitHub
sub-issues may live in another repository. Resolve the scope with
`python3 $WF_TOOLS_EPIC/fetch_epic.py <ref>` and record it in `_state.md` as `Projects:`. For each
project in scope, read `projects/<project>_must_read.md` — **this skill is its only reader** — and
forward `<technical_note>` and `<setup_commands>` into every agent prompt.

## Dispatch

| Phase | File |
|-------|------|
| `research` | `$WF_EPIC/phases/1_research.md` |
| `design` | `$WF_EPIC/phases/2_design.md` |
| `split` | `$WF_EPIC/phases/3_split.md` |
| `implementation` | `$WF_EPIC/phases/4_implementation.md` |
| `status` | run `graph.py --queue <epic-dir>/<epic-slug>_queue.md status` and report |

Phases call forge tools as `$WF_TOOLS_EPIC/<tool>`; the paths written as
`$WF_EPIC/tools/<tool>` in the phase files mean the same thing on GitLab.

Read the file and follow it exactly. The authority for all of it is
`template/epic_workflow.md`; the phase files are its executable form.

## Guardrails

- **Phase gates are real.** Do not start a phase whose input artifact is missing — say what is
  missing and which phase produces it.
- **Never create tickets without explicit confirmation** (phase 3), on either forge. Show every
  title, its project/repository and the parent epic, and wait for a yes.
- **Never push without explicit confirmation.**
- **Commit messages: ≤5 lines, no Claude/Anthropic attribution. Code comments: ≤3 lines.**
- **Conflicts between agents go to the human**, never averaged into a third answer nobody proposed.

## After each phase

Update `<epic-dir>/<epic-slug>_state.md` with the phase, the artifacts written, and the next step.
